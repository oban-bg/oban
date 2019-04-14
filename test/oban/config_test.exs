defmodule Oban.ConfigTest do
  use ExUnit.Case, async: true

  alias Oban.Config

  describe "start_link/1" do
    test "a config struct is stored for retreival" do
      conf = Config.new(repo: Fake.Repo)

      {:ok, pid} = Config.start_link(conf: conf)

      assert %Config{} = Config.get(pid)
    end
  end

  describe "node_name/1" do
    test "the system's DYNO value is favored when available" do
      assert Config.node_name(%{"DYNO" => "worker.1"}) == "worker.1"
    end

    test "the local hostname is used without a DYNO variable" do
      hostname = Config.node_name()

      assert is_binary(hostname)
      assert String.length(hostname) > 1
    end
  end
end
