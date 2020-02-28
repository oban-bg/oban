defmodule Oban.Queue.ExecutorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Oban.Job
  alias Oban.Queue.Executor

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{"mode" => "ok"}, _job), do: :ok
    def perform(%{"mode" => "warn"}, _job), do: {:bad, :this_will_warn}
    def perform(%{"mode" => "raise"}, _job), do: raise(ArgumentError)
    def perform(%{"mode" => "catch"}, _job), do: throw(:no_reason)
    def perform(%{"mode" => "error"}, _job), do: {:error, "no reason"}
  end

  describe "perform/1" do
    defp call_with_mode(mode) do
      Executor.safe_call(%Job{args: %{"mode" => mode}, worker: to_string(Worker)})
    end

    test "accepting :ok as a success" do
      assert {:success, %Job{}} = call_with_mode("ok")
    end

    test "raising, catching and error tuples are failures" do
      assert {:failure, %Job{}, :exception, _, [_ | _]} = call_with_mode("raise")
      assert {:failure, %Job{}, :throw, :no_reason, [_ | _]} = call_with_mode("catch")
      assert {:failure, %Job{}, :error, "no reason", [_ | _]} = call_with_mode("error")
    end

    test "warning on unexpected return values" do
      message = capture_log(fn -> {:success, %Job{}} = call_with_mode("warn") end)

      assert message =~ "Expected #{__MODULE__}.Worker.perform/2"
      assert message =~ "{:bad, :this_will_warn}"
    end
  end
end
