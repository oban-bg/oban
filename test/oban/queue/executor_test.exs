defmodule Oban.Queue.ExecutorTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

  alias Oban.Queue.Executor

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{args: %{"mode" => "ok"}}), do: :ok
    def perform(%{args: %{"mode" => "warn"}}), do: {:bad, :this_will_warn}
    def perform(%{args: %{"mode" => "raise"}}), do: raise(ArgumentError)
    def perform(%{args: %{"mode" => "catch"}}), do: throw(:no_reason)
    def perform(%{args: %{"mode" => "error"}}), do: {:error, "no reason"}
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

  describe "new/2" do
    test "include prefix in metadata for job events" do
      job = %Job{args: %{"mode" => "ok"}, worker: to_string(Worker)}

      assert "public" ==
               [repo: Repo]
               |> Config.new()
               |> Executor.new(job)
               |> Map.from_struct()
               |> get_in([:meta, :prefix])
    end
  end
end
