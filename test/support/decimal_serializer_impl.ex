defimpl Oban.Serializer, for: Decimal do
  @spec serialize(Decimal.t()) :: String.t()
  def serialize(decimal_value), do: Decimal.to_string(decimal_value)
end
