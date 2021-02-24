defmodule Oban.Integration.Worker do
  @moduledoc false

  use Oban.Worker, queue: :alpha

  @impl Worker
  def new(args, opts) do
    opts = Keyword.merge(__opts__(), opts)

    args
    |> Map.new()
    |> Map.put_new(:bin_pid, pid_to_bin())
    |> Job.new(opts)
  end

  @impl Worker
  def perform(%_{args: %{"ref" => ref, "action" => action, "bin_pid" => bin_pid}}) do
    pid = bin_to_pid(bin_pid)

    case action do
      "OK" ->
        send(pid, {:ok, ref})

        :ok

      "DISCARD" ->
        send(pid, {:discard, ref})

        :discard

      "ERROR" ->
        send(pid, {:error, ref})

        {:error, "ERROR"}

      "EXIT" ->
        send(pid, {:exit, ref})

        GenServer.call(FakeServer, :exit)

      "FAIL" ->
        send(pid, {:fail, ref})

        raise RuntimeError, "FAILED"

      "KILL" ->
        send(pid, {:kill, ref})

        Process.exit(self(), :kill)

      "SNOOZE" ->
        send(pid, {:snooze, ref})

        {:snooze, 60}

      "TASK_ERROR" ->
        send(pid, {:async, ref})

        fn -> apply(FakeServer, :call, []) end
        |> Task.async()
        |> Task.await()

        :ok
    end
  end

  def perform(%_{args: %{"ref" => ref, "sleep" => sleep, "bin_pid" => bin_pid}}) do
    pid = bin_to_pid(bin_pid)

    send(pid, {:started, ref})

    :ok = Process.sleep(sleep)

    send(pid, {:ok, ref})

    :ok
  end

  @impl Worker
  def backoff(%_{args: %{"backoff" => backoff}}), do: backoff
  def backoff(%_{} = job), do: Worker.backoff(job)

  @impl Worker
  def timeout(%_{args: %{"timeout" => timeout}}), do: timeout
  def timeout(_job), do: :infinity

  def pid_to_bin(pid \\ self()) do
    pid
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def bin_to_pid(bin) do
    bin
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end
end
