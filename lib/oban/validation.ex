defmodule Oban.Validation do
  @moduledoc false

  alias Oban.Cron.Expression

  @type validator ::
          ({atom(), term()} ->
             :ok
             | {:error, term()})
          | {:unknown, atom() | {atom(), term()}, module()}

  def validate(parent_key \\ nil, opts, validator)

  def validate(_parent_key, opts, validator) when is_list(opts) and is_function(validator, 1) do
    Enum.reduce_while(opts, :ok, fn opt, acc ->
      case validator.(opt) do
        nil -> {:cont, acc}
        :ok -> {:cont, acc}
        {:error, _reason} = error -> {:halt, error}
        {:unknown, field, module} -> {:halt, unknown_error(field, module)}
      end
    end)
  end

  def validate(parent_key, opts, _validator) do
    {:error, "expected #{inspect(parent_key)} to be a list, got: #{inspect(opts)}"}
  end

  @spec validate!(opts :: Keyword.t(), validator()) :: :ok
  def validate!(opts, validator) do
    with {:error, reason} <- validator.(opts), do: raise(ArgumentError, reason)
  end

  def validate_schema(opts, schema) when is_list(schema) do
    Enum.reduce_while(opts, :ok, fn {key, val}, acc ->
      case Keyword.fetch(schema, key) do
        {:ok, type} ->
          case validate_type(type, key, val) do
            :ok -> {:cont, acc}
            error -> {:halt, error}
          end

        :error ->
          {:halt, unknown_error(key, Keyword.keys(schema))}
      end
    end)
  end

  def validate_schema!(opts, schema) do
    with {:error, reason} <- validate_schema(opts, schema) do
      raise ArgumentError, reason
    end
  end

  @doc false
  def validate_integer(key, value, opts \\ []) do
    min = Keyword.get(opts, :min, 1)

    if is_integer(value) and value > min - 1 do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a positive integer, got: #{inspect(value)}"}
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

  # Type Validators

  defp validate_type(:any, _key, _val), do: :ok

  defp validate_type(:atom, key, val) when not is_atom(val) do
    {:error, "expected #{inspect(key)} to be an atom, got: #{inspect(val)}"}
  end

  defp validate_type({:behaviour, module}, key, {val, opts}) do
    with :ok <- validate_type({:behaviour, module}, key, val) do
      if Keyword.keyword?(opts) do
        :ok
      else
        {:error, "expected #{inspect(key)} to be a keyword list, got: #{inspect(opts)}"}
      end
    end
  end

  defp validate_type({:behaviour, module}, key, val) do
    cond do
      not Code.ensure_loaded?(val) ->
        {:error, "expected #{inspect(key)} to be a loaded module, got: #{inspect(val)}"}

      module not in behaviours(val) ->
        {:error, "expected #{inspect(key)} to implement #{inspect(module)}, got: #{inspect(val)}"}

      true ->
        :ok
    end
  end

  defp validate_type(:boolean, key, val) when not is_boolean(val) do
    {:error, "expected #{inspect(key)} to be a boolean, got: #{inspect(val)}"}
  end

  defp validate_type({:enum, list}, key, val) do
    if val in list do
      :ok
    else
      {:error, "expected #{inspect(key)} to included in #{inspect(list)}, got: #{inspect(val)}"}
    end
  end

  defp validate_type(:falsy, key, val) when not is_nil(val) and val != false do
    {:error, "expected #{inspect(key)} to be falsy, got: #{inspect(val)}"}
  end

  defp validate_type({:function, arity}, key, val) when not is_function(val, arity) do
    {:error, "expected #{inspect(key)} to be #{arity} arity function, got: #{inspect(val)}"}
  end

  defp validate_type(nil, key, val) when not is_nil(val) do
    {:error, "expected #{inspect(key)} to be nil, got: #{inspect(val)}"}
  end

  defp validate_type(:non_neg_integer, key, val) when not is_integer(val) or val < 0 do
    {:error, "expected #{inspect(key)} to be a non negative integer, got: #{inspect(val)}"}
  end

  defp validate_type(:pos_integer, key, val) when not is_integer(val) or val < 1 do
    {:error, "expected #{inspect(key)} to be a positive integer, got: #{inspect(val)}"}
  end

  defp validate_type({:pattern, regex}, key, val) do
    cond do
      not is_binary(val) ->
        {:error, "expected #{inspect(key)} to be a binary, got: #{inspect(val)}"}

      not Regex.match?(regex, val) ->
        {:error, "expected #{inspect(key)} to match #{inspect(regex)}, got: #{inspect(val)}"}

      true ->
        :ok
    end
  end

  defp validate_type({:range, min..max//_}, key, val) when val < min or val > max do
    {:error, "expected #{inspect(key)} to be between #{min}..#{max}, got: #{inspect(val)}"}
  end

  defp validate_type({:module, funs}, key, val) do
    cond do
      not Code.ensure_loaded?(val) ->
        {:error, "expected #{inspect(key)} to be a loaded module, got: #{inspect(val)}"}

      not Enum.all?(funs, fn {fun, arity} -> function_exported?(val, fun, arity) end) ->
        {:error, "expected #{inspect(key)} to implement #{inspect(funs)}, got: #{inspect(val)}"}

      true ->
        :ok
    end
  end

  defp validate_type(:schedule, key, val) do
    case Expression.parse(val) do
      {:ok, _cron} ->
        :ok

      {:error, error} ->
        {:error, "expected #{inspect(key)} to be a valid cron schedule, got: #{error.message}"}
    end
  end

  defp validate_type(:string, key, val) when not is_binary(val) do
    {:error, "expected #{inspect(key)} to be a string, got: #{inspect(val)}"}
  end

  defp validate_type(:timeout, key, val)
       when (not is_integer(val) or val < 0) and val != :infinity do
    {:error,
     "expected #{inspect(key)} to be a positive integer or :infinity, got: #{inspect(val)}"}
  end

  defp validate_type(:timezone, key, val) do
    if is_binary(val) and match?({:ok, _}, DateTime.now(val)) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a known timezone, got: #{inspect(val)}"}
    end
  end

  defp validate_type({:custom, fun}, key, val) when is_function(fun, 1) do
    with {:error, message} <- fun.(val) do
      {:error, "invalid value for #{inspect(key)}, #{message}"}
    end
  end

  defp validate_type({:list, type}, key, val) when is_list(val) do
    if Enum.all?(val, &(:ok == validate_type(type, key, &1))) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a list of #{inspect(type)}, got: #{inspect(val)}"}
    end
  end

  defp validate_type({:list, _type}, key, val) do
    {:error, "expected #{inspect(key)} to be a list, got: #{inspect(val)}"}
  end

  defp validate_type({:or, types}, key, val) do
    if Enum.any?(types, &(:ok == validate_type(&1, key, val))) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be one of #{inspect(types)}, got: #{inspect(val)}"}
    end
  end

  defp validate_type(_type, _key, _val), do: :ok

  defp behaviours(module) do
    :attributes
    |> module.__info__()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp unknown_error({name, _value}, known), do: unknown_error(name, known)

  defp unknown_error(name, module) when is_atom(module) do
    known =
      module
      |> struct([])
      |> Map.from_struct()
      |> Map.keys()

    unknown_error(name, known)
  end

  defp unknown_error(name, known) do
    name = to_string(name)

    known
    |> Enum.map(fn field -> {String.jaro_distance(name, to_string(field)), field} end)
    |> Enum.sort(:desc)
    |> case do
      [{score, field} | _] when score > 0.7 ->
        {:error, "unknown option :#{name}, did you mean :#{field}?"}

      _ ->
        {:error, "unknown option :#{name}"}
    end
  end
end
