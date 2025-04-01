# Oban Anti-Patterns Guide

## Introduction

[Oban](https://github.com/oban-bg/oban) is a robust job processing system for Elixir, providing applications with reliability, persistence, and concurrency for background job processing. Despite its excellent design, even experienced developers can fall into patterns that undermine Oban's effectiveness or create maintenance challenges.

This guide identifies common anti-patterns when working with Oban and provides concrete refactoring strategies. By recognizing and avoiding these anti-patterns, you'll create more maintainable, performant, and reliable background job systems that better leverage Oban's architecture.

## Anti-Pattern 1: Using Recorded Jobs as Domain Data Storage

### Problem

Oban Pro's `recorded: true` option preserves job results for workflow coordination. However, some developers misuse this feature as a primary storage mechanism for domain data that should reside in dedicated database tables.

**Why this is problematic:**

- **Data lifecycle mismatch**: Jobs are designed to be ephemeral while domain data often requires long-term persistence
- **Data loss risk**: Recorded data is lost when jobs are pruned (which is a necessary maintenance operation)
- **Query limitations**: Retrieving data from job records is inefficient compared to properly designed schemas
- **Architectural coupling**: Creates an inappropriate dependency between background processing and core domain data

### Example

```elixir
defmodule MyApp.Workers.ExternalEntityImporter do
  use Oban.Pro.Workers.Workflow, recorded: true, queue: :imports

  @impl true
  def process(%Job{args: %{"external_id" => external_id}}) do
    # Fetch and transform external data
    {:ok, response} = MyApp.ExternalAPI.fetch_entity(external_id)

    # Store essential domain data in the job record instead of a proper table
    {:ok, %{id: response.id, name: response.name, details: response.details}}
  end
end

defmodule MyApp.Workers.ExternalEntityProcessor do
  use Oban.Pro.Workers.Workflow, queue: :processing

  @impl true
  def process(%Job{args: args} = job) do
    # Retrieve domain data from the recorded job rather than from a proper DB table
    with {:ok, entity} <- fetch_entity_data(job) do
      # Process the entity using data from the recorded job
      MyApp.Processor.process_entity(entity)
    end
  end

  defp fetch_entity_data(job) do
    job
    |> Oban.Pro.Workers.Workflow.all_jobs(names: ["import_entity"])
    |> List.first()
    |> fetch_recorded()
  end
end
```

### Refactoring

Create proper domain models and use jobs only for processing coordination:

```elixir
defmodule MyApp.Workers.ExternalEntityImporter do
  use Oban.Pro.Workers.Workflow, queue: :imports

  @impl true
  def process(%Job{args: %{"external_id" => external_id}}) do
    with {:ok, response} <- MyApp.ExternalAPI.fetch_entity(external_id),
         # Store the entity in a dedicated database table
         {:ok, entity} <- MyApp.Entities.create_entity(%{
           external_id: external_id,
           name: response.name,
           details: response.details
         }) do
      # Pass only the reference ID in the job result
      {:ok, %{entity_id: entity.id}}
    end
  end
end

defmodule MyApp.Workers.ExternalEntityProcessor do
  use Oban.Pro.Workers.Workflow, queue: :processing

  @impl true
  def process(%Job{args: %{"entity_id" => entity_id}}) do
    # Retrieve data from a proper database table
    with {:ok, entity} <- MyApp.Entities.get_entity(entity_id) do
      MyApp.Processor.process_entity(entity)
    end
  end
end
```

### Additional Remarks

- ✅ Use `recorded: true` for **workflow coordination data only**
- ✅ Create proper Ecto schemas for domain entities
- ✅ Pass only references (IDs) between workflow steps
- ✅ Design database schemas independently of your background job structure
- ✅ Consider workflow jobs as operations on data, not storage for data

## Anti-Pattern 2: Using Workflows for Simple Sequential Operations

### Problem

Oban Pro offers both Workflows and Chained Jobs for coordinating sequential operations. Using Workflows merely to enforce job ordering when Chain Workers would suffice introduces unnecessary complexity and performance overhead.

This anti-pattern specifically applies to cases where Workflows are used as a flow control mechanism with jobs being perpetually appended to enforce sequential processing. A linear workflow with a defined end, however, is perfectly appropriate.

When you misuse Workflows for simple sequential processing:
- You create more complex dependency tracking than necessary
- You make your code harder to understand and maintain

### Example

Using Workflows primarily to ensure webhook events for an account are processed in order:

```elixir
defmodule MyApp.WebhookProcessor do
  alias Oban.Pro.Workers.Workflow
  
  def process_webhook(account_id, event) do
    # Find the most recent webhook job for this account
    previous_job =
      Oban.Job
      |> where([j], j.worker == "MyApp.Workers.WebhookHandler")
      |> where([j], fragment("?->>'account_id' = ?", j.args, ^account_id))
      |> order_by([j], desc: j.inserted_at)
      |> limit(1)
      |> MyApp.Repo.one()
    
    case previous_job do
      nil ->
        # No previous job, create new workflow
        Workflow.new()
        |> Workflow.add(
          :process_webhook,
          MyApp.Workers.WebhookHandler.new(%{
            "account_id" => account_id, 
            "event" => event
          })
        )
        |> Oban.insert_all()
        
      job ->
        # Get workflow_id and job_name to create dependency
        workflow_id = Workflow.workflow_id(job)
        job_name = Workflow.job_name(job)
        
        # Add new job with dependency on previous job to ensure sequential processing
        Workflow.add(
          workflow_id,
          :process_webhook,
          MyApp.Workers.WebhookHandler.new(%{
            "account_id" => account_id, 
            "event" => event
          }),
          deps: [job_name]
        )
    end
  end
end

defmodule MyApp.Workers.WebhookHandler do
  use Oban.Pro.Workers.Workflow, queue: :webhooks, max_attempts: 3
  
  @impl true
  def process(%Oban.Job{args: %{"account_id" => account_id, "event" => event}}) do
    # Process the webhook event
    MyApp.Webhooks.process_for_account(account_id, event)
  end
end
```

### Refactoring

Use Chain Workers for simpler sequential processing:

```elixir
defmodule MyApp.WebhookProcessor do
  def process_webhook(account_id, event) do
    # Chain Workers handle the ordering automatically
    %{"account_id" => account_id, "event" => event}
    |> MyApp.Workers.WebhookHandler.new()
    |> Oban.insert()
  end
end

defmodule MyApp.Workers.WebhookHandler do
  use Oban.Pro.Workers.Chain, 
    queue: :webhooks, 
    max_attempts: 3,
    # Partition chains by account_id to ensure sequential processing per account
    chain: [by: [args: :account_id]]
  
  @impl true
  def process(%Oban.Job{args: %{"account_id" => account_id, "event" => event}}) do
    # Process the webhook event
    MyApp.Webhooks.process_for_account(account_id, event)
    
    :ok
  end
end
```

### Additional Remarks

When deciding between Workflows and Chain Workers, consider:

| Use Chain Workers When | Use Workflow Workers When |
|--------------------------|---------------------------|
| You need jobs to run in sequence | Jobs have complex dependency relationships |
| Processing order must be maintained | Jobs may have multiple dependencies |
| You need to partition by specific fields | You need conditional branching |
| You have a linear job sequence | Your job graph has a complex structure |

Chain Workers are specifically designed for ensuring sequential processing, with built-in support for partitioning by fields. This provides the same ordering guarantees with less code and better performance.

Remember: Workflows are excellent for complex dependency graphs with a defined end, but for simple sequential processing, Chain Workers are the right tool for the job.

## Anti-Pattern 3: Disconnected Jobs for Connected Operations

### Problem

Creating separate, uncoordinated jobs for operations that logically form a sequence leads to coordination problems, race conditions, and system behavior that's difficult to understand or debug.

**This becomes particularly problematic when:**

- Working with external systems where operation order is critical
- Processing multi-step transactions that must maintain consistency
- Handling event sequences that must preserve chronological order
- Managing operations where later steps depend on earlier results
- Distributing jobs across multiple nodes without coordination

### Example

```elixir
# In one part of the application
defmodule MyApp.ExternalService.CreateDraftOrder do
  use Oban.Worker, queue: :external_service

  @impl Oban.Worker
  def perform(%{args: %{"customer_id" => customer_id, "items" => items}}) do
    {:ok, draft_order} = MyApp.ExternalAPI.create_draft_order(customer_id, items)

    # Job completes successfully, but there's no guarantee the completion job will run next
    {:ok, %{draft_order_id: draft_order.id}}
  end
end

# In another part of the application
defmodule MyApp.ExternalService.CompleteDraftOrder do
  use Oban.Worker, queue: :external_service

  @impl Oban.Worker
  def perform(%{args: %{"draft_order_id" => draft_order_id}}) do
    # This job might run before the draft order is created if scheduling is mismanaged
    MyApp.ExternalAPI.complete_draft_order(draft_order_id)
  end
end

# Usage with uncoordinated job scheduling
%{customer_id: customer.id, items: order_items}
|> MyApp.ExternalService.CreateDraftOrder.new()
|> Oban.insert()

%{draft_order_id: draft_order_id}  # Where does this ID come from?
|> MyApp.ExternalService.CompleteDraftOrder.new()
|> Oban.insert()
```

### Refactoring

Use Chain Workers to ensure proper operation sequencing:

```elixir
defmodule MyApp.ExternalService.CreateDraftOrder do
  use Oban.Pro.Workers.Chain,
    queue: :external_service,
    max_attempts: 3,
    unique: [period: 30]

  @impl true
  def process(%{args: %{"customer_id" => customer_id, "items" => items}}) do
    with {:ok, draft_order} <- MyApp.ExternalAPI.create_draft_order(customer_id, items) do
      # Schedule the completion job to run after this job completes
      %{draft_order_id: draft_order.id, customer_id: customer_id}
      |> MyApp.ExternalService.CompleteDraftOrder.new()
      |> Oban.insert()

      {:ok, %{draft_order_id: draft_order.id}}
    end
  end
end

defmodule MyApp.ExternalService.CompleteDraftOrder do
  use Oban.Pro.Workers.Chain,
    queue: :external_service,
    max_attempts: 3,
    unique: [period: 30]

  @impl true
  def process(%{args: %{"draft_order_id" => draft_order_id}}) do
    # Now guaranteed to run after draft order creation
    MyApp.ExternalAPI.complete_draft_order(draft_order_id)
  end
end

# Now just insert the first job, and the chain handles the rest
%{customer_id: customer.id, items: order_items}
|> MyApp.ExternalService.CreateDraftOrder.new()
|> Oban.insert()
```

### Additional Remarks

You can fine-tune chain behavior to handle special cases:

```elixir
# Customize chain behavior for different error scenarios
use Oban.Pro.Workers.Chain,
  queue: :external_service,
  max_attempts: 3,
  # Stop the entire chain if a job is discarded
  on_discarded: :halt,
  # Continue the chain if a job is cancelled
  on_cancelled: :continue
```

Best practices:
- ✅ Design jobs to reflect logical business operations
- ✅ Make each job idempotent when possible
- ✅ Use chain workers for sequential operations
- ✅ Pass sufficient context between chain steps
- ✅ Consider failure scenarios in your chain design

## Anti-Pattern 4: Using Oban Jobs Instead of Simple Tasks

### Problem

Using Oban jobs for operations that don't benefit from Oban's core features (persistence, retries, scheduling, uniqueness) creates unnecessary overhead and database load. While Oban provides critical guarantees for important background operations, not every concurrent operation requires this level of robustness.

**Signs you might be misusing Oban for simple tasks:**

- Setting `max_attempts: 1` (eliminating retry benefits)
- Jobs with no failure handling or recovery logic
- Operations that complete quickly (milliseconds)
- Fire-and-forget operations where outcomes aren't critical
- Operations that don't need to survive application restarts

### Example

```elixir
defmodule MyApp.Notifications.SendAnalyticsEvent do
  use Oban.Worker,
    queue: :analytics,
    max_attempts: 1,  # No retries
    priority: 0       # Not prioritized

  @impl Oban.Worker
  def perform(%{args: %{"event" => event, "properties" => properties}}) do
    # Simple fire-and-forget analytics event
    MyApp.Analytics.track_event(event, properties)

    :ok  # Always succeeds (or we don't care if it fails)
  end
end

# Usage that adds database overhead for a simple operation
%{event: "page_view", properties: %{page: "/dashboard"}}
|> MyApp.Notifications.SendAnalyticsEvent.new()
|> Oban.insert()
```

### Refactoring

Use Task for simple, non-critical operations where best-effort execution is sufficient:

```elixir
defmodule MyApp.Notifications do
  def send_analytics_event(event, properties) do
    Task.start(fn ->
      MyApp.Analytics.track_event(event, properties)
    end)
  end
end

# Usage without database overhead
MyApp.Notifications.send_analytics_event("page_view", %{page: "/dashboard"})
```

For slightly more robust handling with supervision and concurrency control:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other children
      {Task.Supervisor, name: MyApp.TaskSupervisor, max_children: 100}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule MyApp.Notifications do
  def send_analytics_event(event, properties) do
    Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
      MyApp.Analytics.track_event(event, properties)
    end)
  end
end
```

### Additional Remarks

Oban picks up where Tasks leave off, providing critical infrastructure for mission-critical background operations. Choose based on your specific requirements:

| Use Oban When You Need | Use Tasks When You Have |
|------------------------|------------------------|
| **Persistence** across application restarts | Operations that can be lost on restart |
| **Scheduled execution** at a future time | Operations that run immediately |
| **Automatic retries** with configurable backoff | One-time operations with no retry needs |
| **Rate limiting** and concurrency control | Operations where Task.Supervisor limits suffice |
| **Distribution** across multiple nodes | Simple local concurrent operations |
| **Uniqueness guarantees** to prevent duplicates | Operations where duplicates are acceptable |
| **Historical observability** for auditing/debugging | Fire-and-forget operations with minimal logging |
| **Runtime instrumentation** and dashboards | Operations that don't need detailed monitoring |
| **Critical business processes** that must complete | Non-critical background processing |

Remember that while Tasks are lighter weight, they offer far fewer guarantees. If your operation needs persistence, scheduling, retries, or any other robust features, Oban is the appropriate solution.

## Anti-Pattern 5: Retaining Oban Jobs Indefinitely for State

### Problem

Keeping Oban jobs in the database indefinitely for historical or reference purposes leads to:

- Database bloat and degraded query performance
- Increased backup and maintenance costs
- Potential scaling issues as job volume grows
- Dependency on a table designed for transient data

### Example

Insufficient job pruning configuration:

```elixir
config :my_app, Oban,
  engine: Oban.Pro.Engines.Smart,
  repo: MyApp.Repo,
  plugins: [
    # No pruner configured, or pruner with excessive retention
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 365}, # 1 year
    Oban.Pro.Plugins.DynamicLifeline
  ],
  queues: [default: 10, external_service: 5]
```

Code that improperly relies on long-term job persistence:

```elixir
defmodule MyApp.Reports do
  def generate_monthly_report(year, month) do
    # Problematic: Relies on jobs to remain in the database indefinitely
    jobs =
      Oban.Job
      |> where([j], j.worker == "MyApp.Workers.InvoiceProcessor")
      |> where([j], j.state == "completed")
      |> where([j], fragment("?->>'year' = ?", j.args, ^to_string(year)))
      |> where([j], fragment("?->>'month' = ?", j.args, ^to_string(month)))
      |> MyApp.Repo.all()

    # Process jobs for reporting
    process_jobs_for_report(jobs)
  end
end
```

### Refactoring

Use appropriate pruning configuration with Oban Pro's full range of options:

```elixir
config :my_app, Oban,
  engine: Oban.Pro.Engines.Smart,
  repo: MyApp.Repo,
  plugins: [
    # Comprehensive pruning strategy with different retention periods
    {Oban.Plugins.Pruner, 
      # Standard states can be pruned fairly quickly
      max_age: 60 * 60 * 24 * 7,            # 1 week for completed/cancelled
      # Keep failures longer for investigation
      max_age_failure: 60 * 60 * 24 * 30,   # 30 days for failed jobs
      # Limit total jobs regardless of age
      limit: 250_000                        # Cap total jobs
    },
    Oban.Pro.Plugins.DynamicLifeline
  ],
  queues: [default: 10, external_service: 5]
```

Create a dedicated schema for job results that need longer retention:

```elixir
defmodule MyApp.Schema.JobResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "job_results" do
    field :job_type, :string
    field :parameters, :map
    field :result, :map
    field :year, :integer
    field :month, :integer
    field :processed_at, :utc_datetime

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:job_type, :parameters, :result, :year, :month, :processed_at])
    |> validate_required([:job_type, :processed_at])
  end
end

defmodule MyApp.JobResults do
  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Schema.JobResult

  def create(attrs) do
    %JobResult{}
    |> JobResult.changeset(attrs)
    |> Repo.insert()
  end

  def get_by_period(job_type, year, month) do
    JobResult
    |> where([r], r.job_type == ^job_type)
    |> where([r], r.year == ^year)
    |> where([r], r.month == ^month)
    |> Repo.all()
  end
end
```

Store meaningful job outcomes in the dedicated table:

```elixir
defmodule MyApp.Workers.InvoiceProcessor do
  use Oban.Worker, queue: :invoices

  @impl Oban.Worker
  def perform(%{args: %{"invoice_id" => invoice_id, "year" => year, "month" => month}}) do
    with {:ok, result} <- MyApp.Invoices.process(invoice_id) do
      # Store the result in a dedicated table for long-term access
      MyApp.JobResults.create(%{
        job_type: "invoice_processor",
        parameters: %{invoice_id: invoice_id},
        result: result,
        year: year,
        month: month,
        processed_at: DateTime.utc_now()
      })

      {:ok, result}
    end
  end
end

defmodule MyApp.Reports do
  def generate_monthly_report(year, month) do
    # Query from a dedicated table designed for long-term storage
    job_results = MyApp.JobResults.get_by_period("invoice_processor", year, month)

    # Process results for reporting
    process_results_for_report(job_results)
  end
end
```

### Additional Remarks

Consider various approaches based on your specific needs:

| Approach | Best For |
|----------|----------|
| Dedicated database tables | Queryable data that fits your domain model |
| Event sourcing | Complete historical record of system events |
| Read models | Pre-aggregated data for reporting |
| Periodic data exports | Archive data that rarely needs to be queried |
| External logging systems | Audit trails and operational visibility |

## Anti-Pattern 6: Placing All Jobs in the Default Queue

### Problem

Using the default queue for all job types ignores the different characteristics, resource requirements, and priorities of various background operations. This leads to:

- Resource contention between quick and long-running jobs
- Priority inversion (critical jobs waiting behind non-critical ones)
- Poor overall system throughput
- Difficulty in monitoring and troubleshooting

### Example

```elixir
defmodule MyApp.Workers.QuickEmailNotification do
  # Missing queue definition - will use :default
  use Oban.Worker

  @impl Oban.Worker
  def perform(%{args: %{"user_id" => user_id, "message" => message}}) do
    # Quick operation that shouldn't be blocked
    MyApp.Notifications.email_user(user_id, message)
  end
end

defmodule MyApp.Workers.LongRunningReportGenerator do
  # Also using default queue - will block other jobs
  use Oban.Worker

  @impl Oban.Worker
  def perform(%{args: %{"report_id" => report_id}}) do
    # Long-running operation that could block other jobs for minutes
    MyApp.Reports.generate_report(report_id)
  end
end
```

### Refactoring

Create a thoughtful queue structure based on job characteristics, leveraging Oban Pro's Smart Engine for dynamic concurrency:

```elixir
# In configuration
config :my_app, Oban,
  engine: Oban.Pro.Engines.Smart,
  repo: MyApp.Repo,
  plugins: [...],
  queues: [
    default: 10,         # General purpose queue
    notifications: 20,    # High concurrency for quick operations
    reports: 2,           # Limited concurrency for resource-intensive operations
    external_api: 5       # Controlled concurrency for external API calls
  ]
```

Assign jobs to appropriate queues:

```elixir
defmodule MyApp.Workers.QuickEmailNotification do
  use Oban.Worker,
    queue: :notifications,  # High-throughput queue
    priority: 1             # Higher priority (lower number)

  @impl Oban.Worker
  def perform(%{args: %{"user_id" => user_id, "message" => message}}) do
    MyApp.Notifications.email_user(user_id, message)
  end
end

defmodule MyApp.Workers.LongRunningReportGenerator do
  use Oban.Worker,
    queue: :reports,  # Limited concurrency queue
    priority: 3       # Lower priority (higher number)

  @impl Oban.Worker
  def perform(%{args: %{"report_id" => report_id}}) do
    MyApp.Reports.generate_report(report_id)
  end
end
```

### Additional Remarks

Design your queue structure based on these job characteristics:

| Characteristic | Considerations |
|----------------|---------------|
| **Duration** | Separate quick jobs from long-running ones |
| **Resource usage** | Limit concurrency for resource-intensive operations |
| **Priority** | Use both queues and priority values for fine-grained control |
| **External dependencies** | Create dedicated queues for rate-limited external services |
| **Business importance** | Ensure critical operations get processed first |

The Smart Engine will dynamically adjust concurrency based on job execution patterns, but it works best when you start with thoughtfully designed queue structure.

## Anti-Pattern 7: Insufficient Error Handling in Jobs

### Problem

Jobs with inadequate error handling lead to:

- Unnecessary retries that waste resources
- Masking of issues that should trigger alerts
- Lack of context for troubleshooting
- Unpredictable system behavior under failure conditions

### Example

```elixir
defmodule MyApp.Workers.UserSynchronizer do
  use Oban.Worker, queue: :sync, max_attempts: 20

  @impl Oban.Worker
  def perform(%{args: %{"user_id" => user_id}}) do
    # Poor error handling - will retry even for expected errors
    case MyApp.Users.fetch(user_id) do
      {:ok, user} ->
        MyApp.ExternalService.sync_user(user)

      {:error, _reason} ->
        # Generic error, will trigger retry without context
        raise "Failed to sync user #{user_id}"
    end
  end
end
```

### Refactoring

Implement thoughtful error handling with appropriate retry behavior:

```elixir
defmodule MyApp.Workers.UserSynchronizer do
  use Oban.Worker, queue: :sync, max_attempts: 5
  require Logger

  @impl Oban.Worker
  def perform(%{args: %{"user_id" => user_id} = args, attempt: attempt}) do
    case MyApp.Users.fetch(user_id) do
      {:ok, user} ->
        case MyApp.ExternalService.sync_user(user) do
          {:ok, _} ->
            :ok

          {:error, %{status: 400, reason: reason}} ->
            # Client error - don't retry
            Logger.warn("User sync failed with client error: #{reason}", args: args)
            {:discard, :client_error}

          {:error, %{status: status}} when status >= 500 ->
            # Server error - worth retrying with backoff
            backoff = :math.pow(2, attempt) |> round()
            Logger.warn("User sync failed with server error: #{status}", args: args)
            {:snooze, backoff}

          {:error, :timeout} ->
            # Network issue - worth retrying
            Logger.warn("User sync timed out", args: args)
            {:error, :timeout}
        end

      {:error, :not_found} ->
        # Don't retry when the user doesn't exist
        Logger.info("Cannot sync user #{user_id} - not found", args: args)
        {:discard, :user_not_found}

      {:error, reason} ->
        # Database error - worth retrying
        Logger.error("Failed to fetch user #{user_id}: #{inspect(reason)}", args: args)
        {:error, reason}
    end
  end
end
```

### Additional Remarks

| Return Value | When to Use |
|--------------|-------------|
| `:ok` or `{:ok, result}` | Job completed successfully |
| `{:error, reason}` | Transient error, should be retried |
| `{:discard, reason}` | Expected failure, don't retry |
| `{:snooze, seconds}` | Temporary issue, retry after delay |
| `{:cancel, reason}` | Cancel this job and dependent jobs |

Additional recommendations:

- ✅ Log context-rich information for all errors
- ✅ Use exponential backoff for retries
- ✅ Set appropriate `max_attempts` values based on error types
- ✅ Consider uniqueness constraints for idempotency
- ✅ Use structured error returns rather than exceptions

## Best Practices for Oban Usage

### Job Design Principles

1. **Make jobs focused and cohesive**
   - Each job should do one thing well
   - Keep job implementations small and maintainable
   - Extract complex logic into domain services

2. **Design for idempotency**
   - Jobs should be safely retriable without side effects
   - Use database transactions for multi-step operations
   - Implement guard clauses to prevent duplicate processing

3. **Pass minimal job arguments**
   - Include only the data needed to identify resources (IDs)
   - Retrieve full data from the database at execution time
   - Consider JSON size limits for job arguments

### Workflow Design Patterns

1. **Choose the right coordination pattern:**
   - **Chain workers**: Simple linear sequences
   - **Workflow workers**: Complex dependencies with branching
   - **Batch workers**: Parallel operations with aggregation

2. **Design queue structure deliberately:**
   - Group similar jobs by characteristics
   - Set appropriate concurrency limits
   - Consider priority and resource usage

3. **Implement comprehensive error handling:**
   - Distinguish between retryable and non-retryable errors
   - Use appropriate return values (`{:discard, reason}`, `{:snooze, seconds}`)
   - Log sufficient context for debugging

### Operational Considerations

1. **Monitor job performance:**
   - Track queue depths and processing times
   - Alert on unusual failure rates
   - Use Oban Web dashboard for visualization

2. **Implement proper pruning policies:**
   - Set reasonable `max_age` values
   - Consider separate retention for different job states
   - Store important results in domain-specific tables

3. **Test job behavior thoroughly:**
   - Use `Oban.Testing` to verify worker behavior
   - Test error cases and retry logic
   - Verify job coordination patterns
