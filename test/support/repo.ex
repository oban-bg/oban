defmodule Oban.Test.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :oban,
    adapter: Ecto.Adapters.Postgres

  def reload(%{__struct__: queryable, id: id}) do
    get(queryable, id)
  end
end
