defmodule Oban.Errors do
  @moduledoc false

  @optional_errors for mod <- [MyXQL.Error, Postgrex.Error],
                       Code.ensure_loaded?(mod),
                       do: mod

  @database_errors [DBConnection.ConnectionError | @optional_errors]
  @retryable_errors [UndefinedFunctionError | @database_errors]

  @doc false
  defmacro database_errors, do: @database_errors

  @doc false
  defmacro retryable_errors, do: @retryable_errors

  if Code.ensure_loaded?(Postgrex.Error) do
    def expected_error?(%Postgrex.Error{postgres: %{code: code}})
        when code in [:deadlock_detected, :lock_not_available, :serialization_failure],
        do: true
  end

  if Code.ensure_loaded?(MyXQL.Error) do
    def expected_error?(%MyXQL.Error{mysql: %{code: code}}) when code in [1205, 1213], do: true
  end

  def expected_error?(_error), do: false
end
