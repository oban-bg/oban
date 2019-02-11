ExUnit.start()

Oban.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Oban.Test.Repo, :manual)

defmodule Oban.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Oban.Test.Repo

  using do
    quote do
      alias Oban.Job
      alias Repo
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    {:ok, %{}}
  end
end
