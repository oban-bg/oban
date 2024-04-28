defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.Producer
  alias __MODULE__, as: State

  require Logger

  # Give a little extra shutdown time so we can report an unclean shutdown that
  # might leave orphaned jobs
  @extra_shutdown_time 250

  @type option ::
          {:foreman, GenServer.name()}
          | {:conf_name, Oban.name()}
          | {:name, module()}
          | {:producer, GenServer.name()}
          | {:queue, Oban.queue_name()}
          | {:shutdown, timeout()}

  defstruct [:foreman, :producer, :queue, :conf_name, :shutdown, interval: 10]

  @spec child_spec([option]) :: Supervisor.child_spec()
  def child_spec(opts) do
    shutdown =
      case opts[:shutdown] do
        0 -> :brutal_kill
        value when is_integer(value) -> value + @extra_shutdown_time
      end

    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: shutdown}
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, %State{} = state) do
    # There is a chance that the foreman doesn't exist, and we never want to raise another error
    # as part of the shut down process.
    try do
      :ok = Producer.shutdown(state.producer)
      :ok = wait_for_executing(state)
    catch
      :exit, _reason -> :ok
    end

    :ok
  end

  defp wait_for_executing(state, start_time \\ :erlang.monotonic_time(:millisecond)) do
    case DynamicSupervisor.count_children(state.foreman) do
      %{active: 0} ->
        :ok

      _ ->
        if shutdown_time_exceeded?(state, :erlang.monotonic_time(:millisecond) - start_time) do
          print_non_clean_exit_message(state)
          :ok
        else
          :ok = Process.sleep(state.interval)

          wait_for_executing(state, start_time)
        end
    end
  end

  defp print_non_clean_exit_message(%State{conf_name: nil}), do: :ok

  defp print_non_clean_exit_message(%State{} = state) do
    case Oban.check_queue(state.conf_name, queue: state.queue) do
      %{running: []} ->
        :ok

      %{running: running_job_ids} ->
        jobs_message = "(job ids: [#{Enum.join(running_job_ids, ", ")}])"

        Logger.warning(
          "Oban's :#{state.queue} queue was unable to cleanly shutdown in allotted time " <>
            "(:shutdown_grace_period was #{state.shutdown}). Remaining job ids: #{jobs_message}"
        )
    end
  catch
    :exit, reason ->
      Logger.warning("watchman error reason: #{inspect(reason, pretty: true)}")
  end

  defp shutdown_time_exceeded?(%State{shutdown: shutdown}, elapsed_time)
       when is_integer(shutdown) and elapsed_time > shutdown do
    true
  end

  defp shutdown_time_exceeded?(_, _), do: false
end
