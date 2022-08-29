defmodule Oban.Test.Exercise do
  @moduledoc false

  alias Ecto.Multi
  alias Oban.Job

  def check_install do
    changeset = changeset()

    {:ok, _} = Oban.insert(changeset)
    {:ok, _} = Oban.insert(Oban, changeset)
    {:ok, _} = Oban.insert(changeset, timeout: 500)
    {:ok, _} = Oban.insert(Oban, changeset, timeout: 500)

    %Multi{} = Oban.insert(Multi.new(), :job, changeset)
    %Multi{} = Oban.insert(Multi.new(), :job, changeset, timeout: 500)
    %Multi{} = Oban.insert(Oban, Multi.new(), :job, changeset)
    %Multi{} = Oban.insert(Oban, Multi.new(), :job, changeset, timeout: 500)
  end

  defp changeset, do: Job.new(%{}, worker: "FakeWorker")
end
