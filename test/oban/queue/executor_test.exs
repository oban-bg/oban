defmodule Oban.Queue.ExecutorTest do
  use Oban.Case, async: true

  alias Oban.{CrashError, PerformError, TimeoutError}
  alias Oban.Queue.Executor

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{args: %{"mode" => "ok"}}), do: :ok
    def perform(%{args: %{"mode" => "result"}}), do: {:ok, :result}
    def perform(%{args: %{"mode" => "snooze_zero"}}), do: {:snooze, 0}
    def perform(%{args: %{"mode" => "snooze"}}), do: {:snooze, 1}
    def perform(%{args: %{"mode" => "raise"}}), do: raise(ArgumentError)
    def perform(%{args: %{"mode" => "catch"}}), do: throw({:error, :no_reason})
    def perform(%{args: %{"mode" => "error"}}), do: {:error, "no reason"}
    def perform(%{args: %{"mode" => "sleep"}}), do: Process.sleep(10)
    def perform(%{args: %{"mode" => "discard"}}), do: {:discard, :no_reason}
    def perform(%{args: %{"mode" => "timeout"}}), do: Process.sleep(10)

    @impl Worker
    def timeout(%_{args: %{"mode" => "timeout"}}), do: 1
    def timeout(_job), do: :infinity
  end

  @conf Config.new(repo: Repo)

  describe "perform/1" do
    test "accepting :ok as a success" do
      assert %{state: :success, result: :ok} = call_with_mode("ok")
      assert %{state: :success, result: {:ok, :result}} = call_with_mode("result")
    end

    test "reporting :snooze status" do
      assert %{state: :snoozed, snooze: 0} = call_with_mode("snooze_zero")
      assert %{state: :snoozed, snooze: 1} = call_with_mode("snooze")
    end

    test "reporting :discard status" do
      assert %{state: :discard} = call_with_mode("discard")
    end

    test "raising, catching and error tuples are failures" do
      assert %{state: :failure} = call_with_mode("raise")
      assert %{state: :failure, error: %CrashError{}} = call_with_mode("catch")
      assert %{state: :failure, error: %PerformError{}} = call_with_mode("error")
    end

    test "reporting a failure with exhausted retries as :exhausted" do
      job = %Job{args: %{"mode" => "error"}, worker: inspect(Worker), attempt: 1, max_attempts: 1}

      assert %{state: :exhausted, error: %PerformError{}} = exec(job)
    end

    test "reporting missing workers as a :failure" do
      job = %Job{args: %{}, worker: "Not.A.Real.Worker"}

      assert %{state: :failure, error: %RuntimeError{message: "unknown worker" <> _}} =
               @conf
               |> Executor.new(job)
               |> Executor.resolve_worker()
               |> Executor.perform()
    end

    test "reporting timeouts when a job exceeds the configured time" do
      Process.flag(:trap_exit, true)

      call_with_mode("timeout")

      assert_receive {:EXIT, _pid, %TimeoutError{message: message, reason: :timeout}}
      assert message =~ "Worker timed out after 1ms"
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
               |> Executor.normalize_state()
               |> Executor.record_finished()

      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      queue_time_ms = System.convert_time_unit(queue_time, :native, :millisecond)

      assert duration_ms >= 10
      assert queue_time_ms >= 30
    end
  end

  defp call_with_mode(mode) do
    exec(%Job{args: %{"mode" => mode}, worker: to_string(Worker)})
  end

  defp exec(job) do
    @conf
    |> Executor.new(job)
    |> Executor.resolve_worker()
    |> Executor.set_label()
    |> Executor.start_timeout()
    |> Executor.perform()
    |> Executor.normalize_state()
    |> Executor.cancel_timeout()
  end
end
