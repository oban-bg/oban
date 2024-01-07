defmodule Oban.Test.Exercise do
  @moduledoc false

  alias Ecto.Multi
  alias Oban.Job

  def check_insert do
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

  def check_insert_all do
    changeset = changeset()
    stream = Stream.duplicate(changeset, 1)
    wrapper = %{changesets: [changeset]}

    [_ | _] = Oban.insert_all([changeset])
    [_ | _] = Oban.insert_all(Oban, [changeset])
    [_ | _] = Oban.insert_all([changeset], timeout: 500)
    [_ | _] = Oban.insert_all(Oban, [changeset], timeout: 500)

    [_ | _] = Oban.insert_all(stream)
    [_ | _] = Oban.insert_all(Oban, stream)
    [_ | _] = Oban.insert_all(stream, timeout: 500)
    [_ | _] = Oban.insert_all(Oban, stream, timeout: 500)

    [_ | _] = Oban.insert_all(wrapper)
    [_ | _] = Oban.insert_all(Oban, wrapper)
    [_ | _] = Oban.insert_all(wrapper, timeout: 500)
    [_ | _] = Oban.insert_all(Oban, wrapper, timeout: 500)

    %Multi{} = Oban.insert_all(Multi.new(), :job, [changeset])
    %Multi{} = Oban.insert_all(Multi.new(), :job, [changeset], timeout: 500)
    %Multi{} = Oban.insert_all(Oban, Multi.new(), :job, [changeset])
    %Multi{} = Oban.insert_all(Oban, Multi.new(), :job, [changeset], timeout: 500)
  end

  defp changeset, do: Job.new(%{}, worker: "FakeWorker")
end
