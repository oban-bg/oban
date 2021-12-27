defmodule Oban.SenatorTest do
  use Oban.Case, async: true

  alias Oban.{Config, Connection, Registry, Senator}

  property "only a single senator is leader" do
    check all key <- positive_integer(),
              stop <- one_of([:conn, :both]),
              names <- uniq_list_of(atom(:alias), min_length: 2),
              max_runs: 30 do
      senators = for name <- names, do: start_senator(name, key)

      assert [{leader_conf, leader_senn}] = filter_leaders(senators)

      stop_senator(leader_conf.name, stop)

      with_backoff([sleep: 5, total: 20], fn ->
        assert 1 ==
                 senators
                 |> List.delete({leader_conf, leader_senn})
                 |> filter_leaders()
                 |> length()
      end)

      for name <- names, do: stop_senator(name)
    end
  end

  defp start_senator(conf_name, key) do
    conf = Config.new(repo: Repo, name: conf_name)

    conn_name = Registry.via(conf.name, Connection)
    senn_name = Registry.via(conf.name, Senator)

    _con_pid = start_supervised!({Connection, conf: conf, name: conn_name})
    senn_pid = start_supervised!({Senator, conf: conf, interval: 10, key: key, name: senn_name})

    {conf, senn_pid}
  end

  defp stop_senator(conf_name, stop \\ :both) do
    conn_name = Registry.via(conf_name, Connection)
    senn_name = Registry.via(conf_name, Senator)

    if stop in [:conn, :both], do: stop_supervised(conn_name)
    if stop in [:senn, :both], do: stop_supervised(senn_name)
  end

  defp filter_leaders(senators) do
    Enum.filter(senators, fn {_conf, senn} -> Senator.leader?(senn) end)
  end
end
