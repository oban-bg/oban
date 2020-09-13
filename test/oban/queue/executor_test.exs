defmodule Oban.Queue.ExecutorTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

  alias Oban.{CrashError, PerformError}
  alias Oban.Queue.Executor

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{args: %{"mode" => "ok"}}), do: :ok
    def perform(%{args: %{"mode" => "warn"}}), do: {:bad, :this_will_warn}
    def perform(%{args: %{"mode" => "raise"}}), do: raise(ArgumentError)
    def perform(%{args: %{"mode" => "catch"}}), do: throw(:no_reason)
    def perform(%{args: %{"mode" => "error"}}), do: {:error, "no reason"}
    def perform(%{args: %{"mode" => "sleep"}}), do: Process.sleep(10)
  end

  @conf Config.new(repo: Repo)

  describe "perform/1" do
    test "accepting :ok as a success" do
      assert %{state: :success} = call_with_mode("ok")
    end

    test "raising, catching and error tuples are failures" do
      assert %{state: :failure} = call_with_mode("raise")
      assert %{state: :failure, error: %CrashError{}} = call_with_mode("catch")
      assert %{state: :failure, error: %PerformError{}} = call_with_mode("error")
    end

    test "inability to resolve a worker is a failure" do
      job = %Job{args: %{}, worker: "Not.A.Real.Worker"}

      assert %{state: :failure, error: %ArgumentError{}} =
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

      assert_in_delta duration_ms, 10, 10
      assert_in_delta queue_time_ms, 30, 10
    end
  end

  describe "new/2" do
    test "tags are included in the job metadata" do
      now = DateTime.utc_now()

      job = %Job{
        args: %{"mode" => "sleep"},
        worker: to_string(Worker),
        tags: ["my_tag"],
        attempted_at: DateTime.add(now, 30, :millisecond),
        scheduled_at: now
      }

      assert %{meta: %{args: %{"mode" => "sleep"}, tags: ["my_tag"]}} = Executor.new(@conf, job)
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
