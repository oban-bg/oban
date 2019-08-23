defmodule Oban.Integration.RescuingTest do
  use Oban.Case

  alias Oban.{Config, Query}

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 2, gamma: 2, delta: 2]

  test "orphaned jobs are transitioned back to an available state" do
    node = "web.1"
    nonce = "a1b2c3d4"

    insert_job!([ref: 1, action: "OK"], queue: "alpha")
    insert_job!([ref: 2, action: "OK"], queue: "alpha", attempted_by: [node, "alpha", nonce])
    insert_job!([ref: 3, action: "OK"], queue: "gamma", attempted_by: [node, "gamma", nonce])
    insert_job!([ref: 4, action: "OK"], queue: "delta", attempted_by: [node, "delta", nonce])

    start_supervised({Oban, @oban_opts})

    assert_receive {:ok, 1}
    assert_receive {:ok, 2}
    assert_receive {:ok, 3}
    assert_receive {:ok, 4}

    :ok = stop_supervised(Oban)
  end

  test "jobs without recent corresponding beats are transitioned" do
    insert_beat!(node: "web.1", nonce: "aaaaaa", queue: "alpha", inserted_at: seconds_ago(10))
    insert_beat!(node: "web.1", nonce: "bbbbbb", queue: "gamma", inserted_at: seconds_ago(30))
    insert_beat!(node: "web.1", nonce: "cccccc", queue: "delta", inserted_at: seconds_ago(90))

    # Freshly executed by a live producer
    insert_job!(%{}, queue: "alpha", attempted_by: ["web.1", "alpha", "aaaaaa"])
    insert_job!(%{}, queue: "gamma", attempted_by: ["web.1", "gamma", "bbbbbb"])

    # With a mismatched nonce
    insert_job!(%{}, queue: "alpha", attempted_by: ["web.1", "alpha", "bbbbbb"])

    # With a mismatched node
    insert_job!(%{}, queue: "gamma", attempted_by: ["web.2", "gamma", "bbbbbb"])

    # Matches a beat that is past the threshold
    insert_job!(%{}, queue: "delta", attempted_by: ["web.1", "delta", "cccccc"])

    assert {1, _} = Query.rescue_orphaned_jobs(Config.new(repo: Repo), "alpha")
    assert {1, _} = Query.rescue_orphaned_jobs(Config.new(repo: Repo), "gamma")
    assert {1, _} = Query.rescue_orphaned_jobs(Config.new(repo: Repo), "delta")
  end

  defp insert_beat!(opts) do
    opts
    |> Map.new()
    |> Map.put_new(:limit, 1)
    |> Map.put_new(:started_at, seconds_ago(300))
    |> Beat.new()
    |> Repo.insert!()
  end

  # The state is always "executing", which makes the job an orphan
  defp insert_job!(args, opts) do
    opts =
      opts
      |> Keyword.put_new(:queue, "alpha")
      |> Keyword.put_new(:state, "executing")

    args
    |> Worker.new(opts)
    |> Repo.insert!()
  end

  defp seconds_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds)
  end
end
