defmodule Oban.Queue.ExecutorTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

  alias Oban.{CrashError, PerformError}
  alias Oban.Queue.Executor

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{args: %{"mode" => "ok"}}), do: :ok
    def perform(%{args: %{"mode" => "result"}}), do: {:ok, :result}
    def perform(%{args: %{"mode" => "warn"}}), do: {:bad, :this_will_warn}
    def perform(%{args: %{"mode" => "raise"}}), do: raise(ArgumentError)
    def perform(%{args: %{"mode" => "catch"}}), do: throw(:no_reason)
    def perform(%{args: %{"mode" => "error"}}), do: {:error, "no reason"}
    def perform(%{args: %{"mode" => "sleep"}}), do: Process.sleep(10)
    def perform(%{args: %{"mode" => "timed"}}), do: Process.sleep(10)

    @impl Worker
    def timeout(%{args: %{"mode" => "timed"}}), do: 20
    def timeout(_), do: :infinity
  end

  @conf Config.new(repo: Repo)

  describe "perform/1" do
    test "accepting :ok as a success" do
      assert %{state: :success, result: :ok} = call_with_mode("ok")
      assert %{state: :success, result: {:ok, :result}} = call_with_mode("result")
    end

    test "raising, catching and error tuples are failures" do
      assert %{state: :failure} = call_with_mode("raise")
      assert %{state: :failure, error: %CrashError{}} = call_with_mode("catch")
      assert %{state: :failure, error: %PerformError{}} = call_with_mode("error")
    end

    test "inability to resolve a worker is a failure" do
      job = %Job{args: %{}, worker: "Not.A.Real.Worker"}

      assert %{state: :failure, error: %RuntimeError{message: "unknown worker" <> _}} =
               @conf
               |> Executor.new(job)
               |> Executor.resolve_worker()
    end

    test "warning on unexpected return values" do
      message = capture_log(fn -> %{state: :success} = call_with_mode("warn") end)

      assert message =~ "Expected #{__MODULE__}.Worker.perform/1"
      assert message =~ "{:bad, :this_will_warn}"
    end

    test "reporting duration and queue_time measurements" do
      now = DateTime.utc_now()

      job = %Job{
        args: %{"mode" => "sleep"},
        worker: to_string(Worker),
        attempted_at: DateTime.add(now, 30, :millisecond),
        scheduled_at: now
      }

      assert %{duration: duration, queue_time: queue_time} =
               @conf
               |> Executor.new(job)
               |> Executor.resolve_worker()
               |> Executor.perform()
               |> Executor.record_finished()

      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      queue_time_ms = System.convert_time_unit(queue_time, :native, :millisecond)

      assert_in_delta duration_ms, 10, 20
      assert_in_delta queue_time_ms, 30, 20
    end

    test "tracking the pid of nested timed tasks" do
      assert %{state: :success, result: :ok} = call_with_mode("timed")

      assert [task_pid] = Process.get(:"$nested")

      assert is_pid(task_pid)
      assert task_pid != self()
    end
  end

  defp call_with_mode(mode) do
    job = %Job{args: %{"mode" => mode}, worker: to_string(Worker)}

    @conf
    |> Executor.new(job)
    |> Executor.resolve_worker()
    |> Executor.perform()
  end
end
