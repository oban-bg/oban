Oban.start_link(repo: Oban.Test.Repo, queues: [])

args = %{expires_at: "2021-01-25", id: "156de198-bfb6-4c1a-be2c-da5b19ebc468"}
meta = %{trace: "72f19313-9e4a-4c51-bb9b-1bc082e4da5e", vsn: "9.68.90"}

insert_all = fn ->
  0..1_000
  |> Enum.map(fn _ -> Oban.Job.new(args, worker: FakeWorker, meta: meta) end)
  |> Oban.insert_all()
end

Benchee.run(%{"Insert All" => insert_all})
