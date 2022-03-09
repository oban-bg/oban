defmodule Oban.Validation do
  @moduledoc false

  @type validator :: ({atom(), term()} -> :ok | {:error, term()})

  @doc """
  A utility to help validate options without resorting to `throw` or `raise` for control flow.

  ## Example

  Ensure all keys are known and the correct type:

      iex> Oban.Validation.validate(name: Oban, fn
      ...>   {:conf, conf} when is_struct(conf) -> :ok
      ...>   {:name, name} when is_atom(name) -> :ok
      ...>   opt -> {:error, "unknown option: " <> inspect(opt)}
      ...> end)
      :ok
  """
  @spec validate(Keyword.t(), validator()) :: :ok | {:error, String.t()}
  def validate(opts, validator) when is_list(opts) and is_function(validator, 1) do
    Enum.reduce_while(opts, :ok, fn opt, acc ->
      case validator.(opt) do
        :ok -> {:cont, acc}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Similar to `validate/2`, but it will raise an `ArgumentError` for any errors.
  """
  @spec validate!(opts :: Keyword.t(), validator()) :: :ok
  def validate!(opts, validator) do
    with {:error, reason} <- validator.(opts), do: raise(ArgumentError, reason)
  end

  # Shared Validations

  @doc false
  def validate_integer(key, value) do
    if is_integer(value) and value > 0 do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a positive integer, got: #{inspect(value)}"}
    end
  end

  @doc false
  def validate_timezone(key, value) do
    if is_binary(value) and match?({:ok, _}, DateTime.now(value)) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a known timezone, got: #{inspect(value)}"}
    end
  end

  @doc false
  def validate_timeout(key, value) do
    if (is_integer(value) and value > 0) or value == :infinity do
      :ok
    else
      {:error,
       "expected #{inspect(key)} to be a positive integer or :infinity, got: #{inspect(value)}"}
    end
  end
end
