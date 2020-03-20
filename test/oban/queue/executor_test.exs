defmodule Oban.Queue.ExecutorTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

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
      job = %Job{args: %{"mode" => mode}, worker: to_string(Worker)}

      Config.new(repo: Repo)
      |> Executor.new(job)
      |> Executor.resolve_worker()
      |> Executor.perform()
    end

    test "accepting :ok as a success" do
      assert %{state: :success} = call_with_mode("ok")
    end

    test "raising, catching and error tuples are failures" do
      assert %{state: :failure} = call_with_mode("raise")
      assert %{state: :failure, error: :no_reason} = call_with_mode("catch")
      assert %{state: :failure, error: "no reason"} = call_with_mode("error")
    end

    test "warning on unexpected return values" do
      message = capture_log(fn -> %{state: :success} = call_with_mode("warn") end)

      assert message =~ "Expected #{__MODULE__}.Worker.perform/2"
      assert message =~ "{:bad, :this_will_warn}"
    end
  end
end
