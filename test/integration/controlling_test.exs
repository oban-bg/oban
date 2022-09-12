defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  test "dispatching jobs from a queue via database trigger" do
    start_supervised_oban!(notifier: Oban.Notifiers.Postgres, queues: [alpha: 5])

    insert!(ref: 1, action: "OK")

    assert_receive {:ok, 1}
  end
end
