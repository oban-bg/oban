# Release Configuration

While having the same Oban configuration for every environment might be fine,
there are certainly times you might want to make changes for a specific
environment. For example, you may want to increase or decrease a queue's
concurrency.

## Using Config Providers

If you are using Elixir Releases, this is straight forward to do using [Module
Config Providers][mcp]:


```elixir
defmodule MyApp.ConfigProvider do
  @moduledoc """
  Provide release configuration for Oban Queue Concurrency
  """

  @behaviour Config.Provider

  def init(path) when is_binary(path), do: path

  def load(config, path) do
    case parse_json(path) do
      nil ->
        config

      queues ->
        Config.Reader.merge(config, ingestion: [{Oban, [queues: queues]}])
    end
  end

  defp parse_json(path) do
    {:ok, _} = Application.ensure_all_started(:jason)

    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("queues")
      |> Keyword.new(fn {key, value} -> {String.to_atom(key), value} end)
    end
  end
end
```

Our config provider ensures that the `Jason` app is loaded so that we can parse
a `JSON` configuration file. Once the JSON is loaded we must extract the
`queues` map and convert it to a keyword list where all of the keys are atoms.
The use of `String.to_atom/1` is safe because all of our queues names are
already defined.

Then you include this in your `mix.exs` file, where your release is configured:

```elixir
releases: [
  umbrella_app: [
    version: "0.0.1",
    applications: [
      child_app: :permanent
    ],
    config_providers: [{Path.To.ConfigProvider, "/etc/config.json"}]
  ]
]
```

Then when you release your app, you ensure that you have a JSON file mounted at
whatever path you specified above and that it contains all of your desired queues:

```json
{"queues": {"special": 1, "default": 10, "events": 20}}
```

[mcp]: https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-config-providers
