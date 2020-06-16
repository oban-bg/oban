defmodule ConfigViaAgent do
  use Agent

  def start_link(opts) when is_list(opts) do
    {conf, opts} = Keyword.pop(opts, :conf)
    Agent.start_link(fn -> conf end, opts)
  end

  def get(name), do: Agent.get(name, & &1)
end

defmodule ConfigViaPersistentTerm do
  def put(name, conf), do: :persistent_term.put(name, conf)
  def get(name), do: :persistent_term.get(name)
end

defmodule Repo do
  def __adapter__, do: :ok
end

name = Bench
conf = Oban.Config.new(repo: Repo)
ConfigViaAgent.start_link(conf: conf, name: name)
ConfigViaPersistentTerm.put(name, conf)

Benchee.run(%{
  "via_agent" => fn -> ConfigViaAgent.get(name) end,
  "via_persistent_term" => fn -> ConfigViaPersistentTerm.get(name) end
})
