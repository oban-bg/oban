Application.ensure_all_started(:postgrex)

Oban.Test.Repo.start_link()
Oban.Test.LiteRepo.start_link()
Oban.Test.UnboxedRepo.start_link()
ExUnit.start(assert_receive_timeout: 500, exclude: [:skip])
Ecto.Adapters.SQL.Sandbox.mode(Oban.Test.Repo, :manual)
