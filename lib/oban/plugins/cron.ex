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
  [perjob]: oban.html#module-periodic-jobs
  """

  use GenServer

  alias Oban.Cron.Expression
  alias Oban.{Config, Job, Query, Worker}

  @type cron_opt ::
          {:args, Job.args()}
          | {:max_attempts, pos_integer()}
          | {:paused, boolean()}
          | {:priority, 0..3}
          | {:queue, atom() | binary()}
          | {:tags, Job.tags()}

  @type cron_input :: {binary(), module(), [cron_opt()]}

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
      interval: :timer.seconds(60),
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

    Query.with_xact_lock(state.conf, state.lock_key, fn ->
      insert_jobs(state.conf, state.crontab, state.timezone)
    end)

    {:noreply, state}
  end

  # Scheduling Helpers

  defp schedule_evaluate(state) do
    timer = Process.send_after(self(), :evaluate, state.interval)

    %{state | timer: timer}
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

  defp validate_opt!({:crontab, crontab}) do
    unless is_list(crontab) and Enum.all?(crontab, &valid_crontab?/1) do
      raise ArgumentError,
            "expected :crontab to be a list of {expression, worker} or " <>
              "{expression, worker, options} tuples"
    end
  end

  defp validate_opt!({:timezone, timezone}) do
    unless is_binary(timezone) and match?({:ok, _}, DateTime.now(timezone)) do
      raise ArgumentError, "expected :timezone to be a known timezone"
    end
  end

  defp validate_opt!(_opt), do: :ok

  defp valid_crontab?({expression, worker, opts}) do
    %Expression{} = Expression.parse!(expression)

    Code.ensure_loaded?(worker) and
      function_exported?(worker, :perform, 1) and
      Keyword.keyword?(opts)
  end

  defp valid_crontab?({expression, worker}), do: valid_crontab?({expression, worker, []})
  defp valid_crontab?(_crontab), do: false

  # Inserting Helpers

  defp insert_jobs(conf, crontab, timezone) do
    {:ok, datetime} = DateTime.now(timezone)

    for {expr, worker, opts} <- crontab, Expression.now?(expr, datetime) do
      {args, opts} = Keyword.pop(opts, :args, %{})

      opts = unique_opts(worker.__opts__(), opts)

      {:ok, _job} = Query.fetch_or_insert_job(conf, worker.new(args, opts))
    end
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
