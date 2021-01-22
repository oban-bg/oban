defmodule UniqueWorker do
  use Oban.Worker, unique: [period: :infinity]

  @impl true
  def perform(_), do: :ok
end

Oban.start_link(repo: Oban.Test.Repo, queues: [])

unique_insert = fn _ ->
  %{id: 1}
  |> UniqueWorker.new()
  |> Oban.insert()
end

Benchee.run(
  %{"Unique Insert" => unique_insert},
  inputs: Map.new([0, 1000, 10_000, 100_000, 1_000_000], fn x -> {to_string(x), x} end),
  before_scenario: fn input ->
    BenchHelper.reset_db()

    (0..input
    |> Enum.chunk_every(5_000)
    |> Enum.each(fn ids ->
      ids
      |> Enum.map(&UniqueWorker.new(%{id: &1}))
      |> Oban.insert_all()
    end))

    Oban.Test.Repo.query!("VACUUM ANALYZE oban_jobs", [], log: false)
  end
)
