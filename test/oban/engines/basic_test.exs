defmodule Oban.Engines.BasicTest do
  use Oban.Case, async: true

  test "inserting jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private")

    Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}))

    assert [%Job{}] = Repo.all(Job, prefix: "private")
  end

  test "inserting unique jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private")
    opts = [unique: [period: 60, fields: [:worker]]]

    Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}, opts))
    Oban.insert!(name, Worker.new(%{ref: 2, action: "OK"}, opts))

    assert [%Job{args: %{"ref" => 1}}] = Repo.all(Job, prefix: "private")
  end

  describe "unique_lock_key/1" do
    @unique [fields: [:worker, :args], keys: [:id], states: [:available, :scheduled]]

    test "hashes uniqueness values rather than the query expression" do
      changeset = Worker.new(%{"id" => 1, "other" => "a"}, unique: @unique)
      %{fields: fields, keys: keys, states: states} = changeset.changes.unique

      keys = Enum.map(keys, &to_string/1)
      states = Enum.map(states, &to_string/1)

      terms =
        Enum.map(fields, fn
          field when field in [:args, :meta] ->
            value =
              changeset
              |> Ecto.Changeset.get_field(field)
              |> Map.new(fn {key, val} -> {to_string(key), val} end)
              |> Map.take(keys)

            {field, value}

          field ->
            {field, Ecto.Changeset.get_field(changeset, field)}
        end)

      assert Oban.Engines.Basic.unique_lock_key(changeset) ==
               :erlang.phash2([keys, states, terms])
    end

    test "ignores args that are not part of the unique keys" do
      left = Worker.new(%{"id" => 1, "other" => "a"}, unique: @unique)
      right = Worker.new(%{"id" => 1, "other" => "b"}, unique: @unique)
      changed = Worker.new(%{"id" => 2, "other" => "a"}, unique: @unique)

      assert Oban.Engines.Basic.unique_lock_key(left) ==
               Oban.Engines.Basic.unique_lock_key(right)

      refute Oban.Engines.Basic.unique_lock_key(left) ==
               Oban.Engines.Basic.unique_lock_key(changed)
    end

    test "stays the same when only the uniqueness period changes" do
      short = [fields: [:worker], period: 60, states: [:available]]
      long = [fields: [:worker], period: 120, states: [:available]]

      left = Worker.new(%{}, unique: short)
      right = Worker.new(%{}, unique: long)

      assert Oban.Engines.Basic.unique_lock_key(left) ==
               Oban.Engines.Basic.unique_lock_key(right)
    end
  end
end
