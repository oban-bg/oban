defmodule Oban.Test.Repo do
  use Ecto.Repo,
    otp_app: :oban,
    adapter: Ecto.Adapters.Postgres
end
