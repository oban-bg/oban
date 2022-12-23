defmodule BenchWorker do
  @moduledoc false

  use Oban.Worker

  @impl Oban.Worker
  def perform(%{args: %{"max" => max, "bin_pid" => bin_pid, "bin_cnt" => bin_cnt}}) do
    pid = BenchHelper.base64_to_term(bin_pid)
    ctn = BenchHelper.base64_to_term(bin_cnt)

    :ok = :counters.add(ctn, 1, 1)

    if :counters.get(ctn, 1) >= max do
      send(pid, :finished)
    end

    :ok
  end
end

counter = :counters.new(1, [])

Oban.Test.Repo.start_link()
Oban.Test.LiteRepo.start_link()

Oban.Test.Repo.query!("TRUNCATE oban_jobs", [], log: false)
Oban.Test.LiteRepo.query!("DELETE FROM oban_jobs", [], log: false)

insert_and_await = fn _engine ->
  :ok = :counters.put(counter, 1, 0)

  args = %{
    max: 1_000,
    bin_pid: BenchHelper.term_to_base64(self()),
    bin_cnt: BenchHelper.term_to_base64(counter)
  }

  0..1_000
  |> Enum.map(fn _ -> BenchWorker.new(args, queue: :default) end)
  |> Oban.insert_all()

  receive do
    :finished -> :ok
  after
    30_000 -> raise "Timeout"
  end
end

Benchee.run(
  %{"Insert & Execute" => insert_and_await},
  inputs: %{
    "Basic" => {Oban.Engines.Basic, Oban.Test.Repo},
    "Lite" => {Oban.Engines.Lite, Oban.Test.LiteRepo}
  },
  before_scenario: fn {engine, repo} ->
    prefix = if engine == Oban.Engines.Lite, do: false, else: "public"

    Oban.start_link(
      engine: engine,
      peer: Oban.Peers.Global,
      prefix: prefix,
      queues: [default: 10],
      repo: repo
    )
  end,
  after_scenario: fn _ ->
    Oban
    |> Oban.Registry.whereis()
    |> Supervisor.stop()
  end
)
