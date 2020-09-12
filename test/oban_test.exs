defmodule ObanTest do
  use ExUnit.Case, async: true

  describe "name" do
    test "can be an arbitrary term" do
      assert {:ok, _} = start_supervised({Oban, name: make_ref(), repo: Oban.Test.Repo})
    end

    test "is by default `Oban`" do
      assert {:ok, pid} = start_supervised({Oban, repo: Oban.Test.Repo})
      assert Oban.whereis(Oban) == pid
    end

    test "must be unique" do
      name = make_ref()
      {:ok, pid} = start_supervised({Oban, name: name, repo: Oban.Test.Repo})

      assert Oban.start_link(name: name, repo: Oban.Test.Repo) ==
               {:error, {:already_started, pid}}
    end

    test "is used as a default child id" do
      assert Supervisor.child_spec(Oban, []).id == Oban
      assert Supervisor.child_spec({Oban, name: :foo}, []).id == :foo
    end
  end

  describe "whereis/1" do
    test "returns pid of the oban root process" do
      name1 = make_ref()
      {:ok, oban1} = start_supervised({Oban, name: name1, repo: Oban.Test.Repo})

      name2 = make_ref()
      {:ok, oban2} = start_supervised({Oban, name: name2, repo: Oban.Test.Repo})

      assert Oban.whereis(name1) == oban1
      assert Oban.whereis(name2) == oban2
    end

    test "returns nil if root process not found" do
      assert is_nil(Oban.whereis(make_ref()))
    end
  end
end
