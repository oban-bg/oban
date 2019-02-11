ExUnit.start()

Oban.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Oban.Test.Repo, :manual)
