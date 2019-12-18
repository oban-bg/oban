defmodule BenchWorker do
  @moduledoc false

  use Oban.Worker

  @impl Oban.Worker
  def perform(%{"max" => max, "bin_pid" => bin_pid, "bin_cnt" => bin_cnt}, _job) do
    pid = BenchHelper.base64_to_term(bin_pid)
    ctn = BenchHelper.base64_to_term(bin_cnt)

    :ok = :counters.add(ctn, 1, 1)

    if :counters.get(ctn, 1) >= max do
      send(pid, :finished)
    end

    :ok
  end
end

queues = [small: 1, medium: 10, large: 100, xlarge: 500]
counter = :counters.new(1, [])

Oban.start_link(repo: Oban.Test.Repo, queues: queues)

BenchHelper.reset_db()

insert_and_await = fn queue ->
  :ok = :counters.put(counter, 1, 0)

  args = %{
    max: 1_000,
    bin_pid: BenchHelper.term_to_base64(self()),
    bin_cnt: BenchHelper.term_to_base64(counter)
  }

  0..1_000
  |> Enum.map(fn _ -> BenchWorker.new(args, queue: queue) end)
  |> Oban.insert_all()

  receive do
    :finished -> :ok
  after
    30_000 -> raise "Timeout"
  end
end

Benchee.run(
  %{"Insert & Execute" => insert_and_await},
  inputs: for({queue, _limit} <- queues, do: {to_string(queue), queue})
)
