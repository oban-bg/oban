defmodule Oban.Plugins.Cron do
  @moduledoc """
  Periodically enqueue jobs through CRON based scheduling.

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

  use GenServer

  alias Oban.Cron.Expression
  alias Oban.{Config, Job, Query, Worker}

  @type cron_input :: {binary(), module()} | {binary(), module(), [Job.option()]}

  @type option ::
          {:conf, Config.t()}
          | {:name, GenServer.name()}
          | {:crontab, [cron_input()]}
          | {:timezone, Calendar.time_zone()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      crontab: [],
      lock_key: 1_149_979_440_242_868_001,
      timezone: "Etc/UTC"
    ]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    validate!(opts)

    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc false
  @spec validate!(Keyword.t()) :: :ok
  def validate!(opts) when is_list(opts) do
    Enum.each(opts, &validate_opt!/1)
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
    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> parse_crontab()

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, %State{} = state) do
    handle_info(:evaluate, state)
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:evaluate, %State{} = state) do
    state = schedule_evaluate(state)

    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case lock_and_insert_jobs(state) do
        {:ok, inserted_jobs} when is_list(inserted_jobs) ->
          {:ok, Map.put(meta, :jobs, inserted_jobs)}

        {:ok, false} ->
          {:ok, Map.put(meta, :jobs, [])}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, state}
  end

  # Scheduling Helpers

  defp schedule_evaluate(state) do
    timer = Process.send_after(self(), :evaluate, interval_to_next_minute())

    %{state | timer: timer}
  end

  # Parsing & Validation Helpers

  defp parse_crontab(%State{crontab: crontab, timezone: timezone} = state) do
    now = DateTime.shift_zone!(DateTime.utc_now(), timezone)

    parsed =
      Enum.map(crontab, fn
        {expression, worker} -> {Expression.parse!(expression, now), worker, []}
        {expression, worker, opts} -> {Expression.parse!(expression, now), worker, opts}
      end)

    %{state | crontab: parsed}
  end

  defp validate_opt!({:crontab, crontab}) do
    unless is_list(crontab) do
      raise ArgumentError, "expected :crontab to be a list, got: #{inspect(crontab)}"
    end

    Enum.each(crontab, &validate_crontab!/1)
  end

  defp validate_opt!({:timezone, timezone}) do
    unless is_binary(timezone) and match?({:ok, _}, DateTime.now(timezone)) do
      raise ArgumentError, "expected :timezone to be a known timezone"
    end
  end

  defp validate_opt!(_opt), do: :ok

  defp validate_crontab!({expression, worker, opts}) do
    %Expression{} = Expression.parse!(expression)

    unless Code.ensure_loaded?(worker) do
      raise ArgumentError, "#{inspect(worker)} not found or can't be loaded"
    end

    unless function_exported?(worker, :perform, 1) do
      raise ArgumentError, "#{inspect(worker)} does not implement `perform/1` callback"
    end

    unless Keyword.keyword?(opts) do
      raise ArgumentError, "options must be a keyword list, got: #{inspect(opts)}"
    end

    unless build_changeset(worker, opts).valid? do
      raise ArgumentError, "expected valid job options, got: #{inspect(opts)}"
    end
  end

  defp validate_crontab!({expression, worker}) do
    validate_crontab!({expression, worker, []})
  end

  defp validate_crontab!(invalid) do
    raise ArgumentError,
          "expected crontab entry to be an {expression, worker} or " <>
            "{expression, worker, options} tuple, got: #{inspect(invalid)}"
  end

  # Inserting Helpers

  defp lock_and_insert_jobs(state) do
    Query.with_xact_lock(state.conf, state.lock_key, fn ->
      insert_jobs(state.conf, state.crontab, state.timezone)
    end)
  end

  defp insert_jobs(conf, crontab, timezone) do
    {:ok, datetime} = DateTime.now(timezone)

    for {expr, worker, opts} <- crontab, Expression.now?(expr, datetime) do
      {:ok, job} = Query.fetch_or_insert_job(conf, build_changeset(worker, opts))

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
    |> Keyword.merge(worker_opts, &Worker.resolve_opts/3)
    |> Keyword.merge(crontab_opts, &Worker.resolve_opts/3)
  end
end
