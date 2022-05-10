defmodule Oban.Plugins.Cron do
  @moduledoc """
  Periodically enqueue jobs through CRON based scheduling.

  This plugin registers workers a cron-like schedule and enqueues jobs automatically. Periodic
  jobs are declared as a list of `{cron, worker}` or `{cron, worker, options}` tuples.

  > #### 🌟 DynamicCron {: .info}
  >
  > This plugin only loads the crontab statically, at boot time. To configure cron schedules
  > dynamically at runtime, across your entire cluster, see the `DynamicCron` plugin in [Oban
  > Pro](https://getoban.pro/docs/pro/dynamic_cron.html).

  ## Using the Plugin

  Schedule various jobs using `{expr, worker}` and `{expr, worker, opts}` syntaxes:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"* * * * *", MyApp.MinuteWorker},
             {"0 * * * *", MyApp.HourlyWorker, args: %{custom: "arg"}},
             {"0 0 * * *", MyApp.DailyWorker, max_attempts: 1},
             {"0 12 * * MON", MyApp.MondayWorker, queue: :scheduled, tags: ["mondays"]},
             {"@daily", MyApp.AnotherDailyWorker}
           ]}
        ]

  ## Options

  * `:crontab` — a list of cron expressions that enqueue jobs on a periodic basis. See [Periodic
    Jobs][perjob] in the Oban module docs for syntax and details.

  * `:timezone` — which timezone to use when scheduling cron jobs. To use a timezone other than
    the default of "Etc/UTC" you *must* have a timezone database like [tzdata][tzdata] installed
    and configured.

  [tzdata]: https://hexdocs.pm/tzdata
  [perjob]: Oban.html#module-periodic-jobs

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Cron` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * :jobs - a list of jobs that were inserted into the database
  """

  @behaviour Oban.Plugin

  use GenServer

  alias Oban.Cron.Expression
  alias Oban.{Job, Peer, Plugin, Repo, Validation, Worker}

  @opaque expression :: Expression.t()

  @type cron_input :: {binary(), module()} | {binary(), module(), [Job.option()]}

  @type option ::
          Plugin.option()
          | {:crontab, [cron_input()]}
          | {:timezone, Calendar.time_zone()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      crontab: [],
      timezone: "Etc/UTC"
    ]
  end

  @impl Plugin
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl Plugin
  def validate(opts) when is_list(opts) do
    Validation.validate(opts, fn
      {:conf, _} -> :ok
      {:crontab, crontab} -> Validation.validate(:crontab, crontab, &validate_crontab/1)
      {:name, _} -> :ok
      {:timezone, timezone} -> Validation.validate_timezone(:timezone, timezone)
      option -> {:error, "unknown option provided: #{inspect(option)}"}
    end)
  end

  @doc """
  Parse a crontab expression into a cron struct.

  This is provided as a convenience for validating and testing cron expressions. As such, the cron
  struct itself is opaque and the internals may change at any time.

  The parser can handle common expressions that use minutes, hours, days, months and weekdays,
  along with ranges and steps. It also supports common extensions, also called nicknames.

  Returns `{:error, %ArgumentError{}}` with a detailed error if the expression cannot be parsed.

  ## Nicknames

  The following special nicknames are supported in addition to standard cron expressions:

    * `@yearly`—Run once a year, "0 0 1 1 *"
    * `@annually`—Same as `@yearly`
    * `@monthly`—Run once a month, "0 0 1 * *"
    * `@weekly`—Run once a week, "0 0 * * 0"
    * `@daily`—Run once a day, "0 0 * * *"
    * `@midnight`—Same as `@daily`
    * `@hourly`—Run once an hour, "0 * * * *"
    * `@reboot`—Run once at boot

  ## Examples

      iex> Oban.Plugins.Cron.parse("@hourly")
      {:ok, #Oban.Cron.Expression<...>}

      iex> Oban.Plugins.Cron.parse("0 * * * *")
      {:ok, #Oban.Cron.Expression<...>}

      iex> Oban.Plugins.Cron.parse("60 * * * *")
      {:error, %ArgumentError{message: "expression field 60 is out of range 0..59"}}
  """
  @spec parse(input :: binary()) :: {:ok, expression()} | {:error, Exception.t()}
  def parse(input) when is_binary(input) do
    expression = Expression.parse!(input)

    {:ok, expression}
  rescue
    error in [ArgumentError] ->
      {:error, error}
  end

  @doc false
  @spec interval_to_next_minute(Time.t()) :: pos_integer()
  def interval_to_next_minute(time \\ Time.utc_now()) do
    time
    |> Time.add(60)
    |> Map.put(:second, 0)
    |> Time.diff(time)
    |> Integer.mod(86_400)
    |> :timer.seconds()
  end

  @impl GenServer
  def init(opts) do
    Validation.validate!(opts, &validate/1)

    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> parse_crontab()
      |> schedule_evaluate()

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:evaluate, %State{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case check_leadership_and_insert_jobs(state) do
        {:ok, inserted_jobs} when is_list(inserted_jobs) ->
          {:ok, Map.put(meta, :jobs, inserted_jobs)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    state =
      state
      |> discard_reboots()
      |> schedule_evaluate()

    {:noreply, state}
  end

  # Scheduling Helpers

  defp schedule_evaluate(state) do
    timer = Process.send_after(self(), :evaluate, interval_to_next_minute())

    %{state | timer: timer}
  end

  defp discard_reboots(state) do
    crontab = Enum.reject(state.crontab, fn {expr, _worker, _opts} -> expr.reboot? end)

    %{state | crontab: crontab}
  end

  # Parsing & Validation Helpers

  defp parse_crontab(%State{crontab: crontab} = state) do
    parsed =
      Enum.map(crontab, fn
        {expression, worker} -> {Expression.parse!(expression), worker, []}
        {expression, worker, opts} -> {Expression.parse!(expression), worker, opts}
      end)

    %{state | crontab: parsed}
  end

  defp validate_crontab({expression, worker, opts}) do
    with {:ok, _} <- parse(expression) do
      cond do
        not Code.ensure_loaded?(worker) ->
          {:error, "#{inspect(worker)} not found or can't be loaded"}

        not function_exported?(worker, :perform, 1) ->
          {:error, "#{inspect(worker)} does not implement `perform/1` callback"}

        not Keyword.keyword?(opts) ->
          {:error, "options must be a keyword list, got: #{inspect(opts)}"}

        not build_changeset(worker, opts).valid? ->
          {:error, "expected valid job options, got: #{inspect(opts)}"}

        true ->
          :ok
      end
    end
  end

  defp validate_crontab({expression, worker}) do
    validate_crontab({expression, worker, []})
  end

  defp validate_crontab(invalid) do
    {:error,
     "expected crontab entry to be an {expression, worker} or " <>
       "{expression, worker, options} tuple, got: #{inspect(invalid)}"}
  end

  # Inserting Helpers

  defp check_leadership_and_insert_jobs(state) do
    if Peer.leader?(state.conf) do
      Repo.transaction(state.conf, fn ->
        insert_jobs(state.conf, state.crontab, state.timezone)
      end)
    else
      {:ok, []}
    end
  end

  defp insert_jobs(conf, crontab, timezone) do
    {:ok, datetime} = DateTime.now(timezone)

    for {expr, worker, opts} <- crontab, Expression.now?(expr, datetime) do
      {:ok, job} = Oban.insert(conf.name, build_changeset(worker, opts))

      job
    end
  end

  defp build_changeset(worker, opts) do
    {args, opts} = Keyword.pop(opts, :args, %{})

    opts = unique_opts(worker.__opts__(), opts)

    worker.new(args, opts)
  end

  # Make each job unique for 59 seconds to prevent double-enqueue if the node or scheduler
  # crashes. The minimum resolution for our cron jobs is 1 minute, so there is potentially
  # a one second window where a double enqueue can happen.
  defp unique_opts(worker_opts, crontab_opts) do
    [unique: [period: 59]]
    |> Worker.merge_opts(worker_opts)
    |> Worker.merge_opts(crontab_opts)
  end
end
