defmodule ObanTest do
  use Oban.Case, async: true

  describe "start_link/1" do
    test "name can be an arbitrary term" do
      assert {:ok, _} = start_supervised({Oban, name: make_ref(), repo: Oban.Test.Repo})
    end

    test "name defaults to `Oban`" do
      assert {:ok, pid} = start_supervised({Oban, repo: Oban.Test.Repo})
      assert Oban.whereis(Oban) == pid
    end

    test "name must be unique" do
      name = make_ref()
      opts = [name: name, repo: Oban.Test.Repo]

      {:ok, pid} = Oban.start_link(opts)
      {:error, {:already_started, ^pid}} = Oban.start_link(opts)
    end

    test "name is used as a default child id" do
      assert Supervisor.child_spec(Oban, []).id == Oban
      assert Supervisor.child_spec({Oban, name: :foo}, []).id == :foo
    end
  end

  describe "whereis/1" do
    test "returning the Oban root process's pid" do
      name_1 = make_ref()
      name_2 = make_ref()

      {:ok, oban_1} = start_supervised({Oban, name: name_1, repo: Repo})
      {:ok, oban_2} = start_supervised({Oban, name: name_2, repo: Repo})

      refute oban_1 == oban_2
      assert Oban.whereis(name_1) == oban_1
      assert Oban.whereis(name_2) == oban_2
    end

    test "returning nil if root process not found" do
      refute Oban.whereis(make_ref())
    end
  end
end
