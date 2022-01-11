defmodule Oban.Plugins.Reindexer do
  @moduledoc """
  Periodically rebuild indexes to minimize database bloat.

  Over time various Oban indexes may grow without `VACUUM` cleaning them up properly. When this
  happens, rebuilding the indexes will release bloat.

  The plugin uses `REINDEX` with the `CONCURRENTLY` option to rebuild without taking any locks
  that prevent concurrent inserts, updates, or deletes on the table.

  Note: This plugin requires the `CONCURRENT` option, which is only available in Postgres 12 and
  above.

  ## Using the Plugin

  By default, the plugin will reindex once a day, at midnight UTC:

      config :my_app, Oban,
        plugins: [Oban.Plugins.Reindexer],
        ...

  To run on a different schedule you can provide a cron expression. For example, you could use the
  `"@weekly"` shorthand to run once a week on Sunday:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Reindexer, schedule: "@weekly"}],
        ...

  ## Options

    * `:schedule` — a cron expression that controls when to reindex. Defaults to `"@midnight"`.

    * `:timezone` — which timezone to use when evaluating the schedule. To use a timezone other than
      the default of "Etc/UTC" you *must* have a timezone database like [tzdata][tzdata] installed
      and configured.

  [tzdata]: https://hexdocs.pm/tzdata
  """

  use GenServer

  alias Oban.{Config, Repo, Senator}
  alias Oban.Cron.Expression
  alias Oban.Plugins.Cron

  @type option :: {:conf, Config.t()} | {:name, GenServer.name()} | {:schedule, binary()}

  defmodule State do
    @moduledoc false

    defstruct [:conf, :name, :schedule, :timer, timezone: "Etc/UTC"]
  end

  @doc false
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl GenServer
  def init(opts) do
    opts =
      opts
      |> Keyword.put_new(:schedule, "@midnight")
      |> Keyword.update!(:schedule, &Expression.parse!/1)

    state = struct!(State, opts)

    {:ok, schedule_reindex(state)}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:reindex, %State{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case check_leadership_and_reindex(state) do
        {:ok, _} ->
          {:ok, meta}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_reindex(state)}
  end

  # Scheduling

  defp schedule_reindex(state) do
    timer = Process.send_after(self(), :reindex, Cron.interval_to_next_minute())

    %{state | timer: timer}
  end

  # Reindexing

  defp check_leadership_and_reindex(state) do
    if Senator.leader?(state.conf) do
      {:ok, datetime} = DateTime.now(state.timezone)

      if Expression.now?(state.schedule, datetime) do
        table = "#{state.conf.prefix}.oban_jobs"

        Repo.query(state.conf, "REINDEX TABLE CONCURRENTLY #{table}", [])
      end
    else
      {:ok, []}
    end
  end
end
