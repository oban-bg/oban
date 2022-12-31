defmodule Oban.TriggerTest do
  use Oban.Case

  @moduletag :unboxed

  test "dispatching jobs from a queue via database trigger" do
    name =
      start_supervised_oban!(
        notifier: Oban.Notifiers.Postgres,
        queues: [dispatch: 5],
        repo: UnboxedRepo,
        prefix: "private"
      )

    Oban.insert!(name, Worker.new(%{ref: 99, action: "OK"}, queue: :dispatch))

    on_exit(fn -> UnboxedRepo.query("DELETE FROM private.oban_jobs WHERE queue = 'dispatch'") end)

    assert_receive {:ok, 99}
  end
end
