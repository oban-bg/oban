defmodule Oban.Integration.DatabaseTriggerTest do
  use Oban.Case

  alias Ecto.Adapters.SQL.Sandbox

  test "dispatching jobs from a queue via database trigger" do
    Sandbox.unboxed_run(Repo, fn ->
      start_supervised_oban!(notifier: Oban.Notifiers.Postgres, queues: [alpha: 5])

      insert!(ref: 1, action: "OK")

      assert_receive {:ok, 1}

      delete_oban_data!()
    end)
  end
end
