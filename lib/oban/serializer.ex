defprotocol Oban.Serializer do
  @fallback_to_any true
  @spec serialize(value :: any()) :: any()
  def serialize(value)
end

defimpl Oban.Serializer, for: Any do
  def serialize(value), do: value
end
