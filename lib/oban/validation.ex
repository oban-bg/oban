defmodule Oban.Validation do
  @moduledoc false

  @type validator :: ({atom(), term()} -> :ok | {:error, term()})

  @doc """
  A utility to help validate options without resorting to `throw` or `raise` for control flow.

  ## Example

  Ensure all keys are known and the correct type:

      validate(opts, fn
        {:conf, conf} when is_struct(conf) -> :ok
        {:name, name} when is_atom(name) -> :ok
        opt -> {:error, "unknown option: " <> inspect(opt)}
      end)
  """
  @spec validate(Keyword.t(), validator()) :: :ok | {:error, String.t()}
  def validate(opts, validator) do
    Enum.reduce_while(opts, :ok, fn opt, acc ->
      case validator.(opt) do
        :ok -> {:cont, acc}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  @spec validate!(opts :: Keyword.t(), validator()) :: :ok
  def validate!(opts, validator) do
    with {:error, reason} <- validate(opts, validator), do: raise(ArgumentError, reason)
  end
end
