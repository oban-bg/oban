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
end
