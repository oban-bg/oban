defmodule Oban.Integration.ExecutionTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM

  require Logger

  @moduletag timeout: :infinity
  @moduletag capture_log: true

  @queues ~w(alpha beta gamma delta)

  defmodule TestOban do
    use Oban, queues: [alpha: 5, beta: 5, gamma: 5, delta: 5]
  end

  defmodule Worker do
    def call(%Oban.Job{args: _args}, %Oban.Config{}) do
      true
    end
  end

  property "jobs are continuously executed", [:verbose] do
    forall commands in commands(__MODULE__) do
      unless Process.whereis(TestOban) do
        TestOban.start_link()
      end

      {history, state, result} = run_commands(__MODULE__, commands)

      (result == :ok)
      |> aggregate(command_names(commands))
      |> when_fail(
        IO.puts("""
        History: #{inspect(history, pretty: true)}
        State: #{inspect(state, pretty: true)}
        Result: #{inspect(result, pretty: true)}
        """)
      )
    end
  end

  # Oban Helpers

  def queue do
    oneof(@queues)
  end

  def args do
    fixed_list([bool(), integer()])
  end

  # State Model

  def initial_state, do: %{pending: 0, success: 0, failure: 0}

  # Pushing a processable job into a known queue succeeds
  # Pushing a processable job into an unknown queue is pending
  # Pushing a job with an unknown worker fails
  # Pushing an unprocessable job with a known worker fails
  def command(_state) do
    oneof([{:call, TestOban, :push, [[args: args(), queue: queue(), worker: Worker]]}])
  end

  def precondition(_state, {:call, _mod, _fun, _args}), do: true

  def postcondition(_state, {:call, _mod, _fun, _args}, _res), do: true

  def next_state(state, _res, {:call, _mod, _fun, _args}) do
    state
  end

  # Any job where the initial argument is `true` will succeed. All other jobs can be considered
  # failures.
  # def next_state(state, _value, {:call, _, :push, opts}) do
  #   case Keyword.get(opts, :args) do
  #     [true | _] ->
  #       %{state | success: state.success + 1}
  #     _ ->
  #       %{state | failure: state.failure + 1}
  #   end
  # end

  # def next_state(state, {:ok, oban}, {:call, _, :start_oban, _}) do
  #   %{state | oban: oban}
  # end

  # def next_state(state, _res, {:call, _, :start_oban, _}) do
  #   state
  # end
end
