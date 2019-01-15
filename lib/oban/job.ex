defmodule Oban.Job do
  @moduledoc false

  @type t :: %__MODULE__{
          args: list(term()),
          id: binary(),
          queue: binary(),
          worker: binary()
        }

  @enforce_keys [:args, :queue, :worker]
  defstruct [:id, :queue, :worker, args: []]

  @spec new(map()) :: t()
  def new(opts) do
    # TODO: validate each part, use properties for this
    struct!(__MODULE__, opts)
  end
end
