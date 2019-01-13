defmodule Oban.Integration.ExecutionTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM

  require Logger

  @moduletag timeout: :infinity
  @moduletag capture_log: true

  @streams [alpha: 5, beta: 5, gamma: 5, delta: 5]

  defmodule State do
    defstruct oban: :empty, pending: 0, success: 0, failure: 0
  end

  property "jobs are continuously executed" do
    forall commands in commands(__MODULE__) do
      # flush redis?

      {history, state, result} = run_commands(__MODULE__, commands)

      (result == :ok)
      |> when_fail(
        IO.puts("""
        History: #{inspect(history, pretty: true)}
        State: #{inspect(state, pretty: true)}
        Result: #{inspect(result, pretty: true)}
        """)
      )
      |> aggregate(command_names(cmds))
    end
  end

  # Oban Helpers

  def start_oban do
    Oban.start_link(streams: @streams)
  end

  def stream do
    streams = Keyword.keys(@streams)

    one_of(streams)
  end

  def args do
    fixed_list([bool(), oneof([integer(), string()])])
  end

  # State Model

  def initial_state, do: %State{}

  def command(%{oban: :empty}) do
    {:call, __MODULE__, :start_oban, []}
  end

  def command(%{oban: oban}) do
    oneof([{:call, Oban, :push, [oban, [args: args(), stream: stream(), worker: @worker]]}])
  end

  def precondition(%{oban: :empty}, {:call, Oban, _, _}), do: false
  def precondition(_, _), do: true

  # Any job where the initial argument is `true` will succeed. All other jobs can be considered
  # failures.
  def next_state(state, _value, {:call, _, :push, [_, [args: [true | _] | _]]}) do
    %{state | success: state.success + 1}
  end

  def next_state(state, _value, {:call, _, :push, [_, _]}) do
    %{state | failure: state.failure + 1}
  end

  def next_state(state, {:ok, oban}, {:call, _, :start_oban, _}) do
    %{state | oban: oban}
  end

  def next_state(state, _, {:call, _, :start_oban, _}) do
    state
  end

  def postcondition(%{success: succ, failure: fail}, {:call, Oban, :push, [_, opts]}, result) do
    # Can I do a postcondition? The execution is asynchronous and won't necessarily be accurate.
  end

  def postcondition(_, _, _), do: true
end
