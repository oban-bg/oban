defmodule Oban.Test.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :oban,
    adapter: Ecto.Adapters.Postgres
end

defmodule Oban.Test.DynamicRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :oban,
    adapter: Ecto.Adapters.Postgres

  def init(_, _) do
    {:ok, Oban.Test.Repo.config()}
  end
end

defmodule Oban.Test.LiteRepo do
  @moduledoc false

  use Ecto.Repo, otp_app: :oban, adapter: Ecto.Adapters.SQLite3
end

defmodule Oban.Test.UnboxedRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :oban,
    adapter: Ecto.Adapters.Postgres

  def init(_, _) do
    config = Oban.Test.Repo.config()

    {:ok, Keyword.delete(config, :pool)}
  end
end
