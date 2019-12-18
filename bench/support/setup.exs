Oban.Test.Repo.start_link()

defmodule BenchHelper do
  def reset_db do
    Oban.Test.Repo.query!("TRUNCATE oban_beats", [], log: false)
    Oban.Test.Repo.query!("TRUNCATE oban_jobs", [], log: false)
  end

  def term_to_base64(term) do
    term
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def base64_to_term(bin) do
    bin
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end
end

