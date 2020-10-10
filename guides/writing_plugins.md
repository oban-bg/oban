# Writing Plugins

Oban supports the use of plugins to extend its base functionality. A plugin is
any module that begins a process and exposes a `start_link/1` function. That
means a plugin may be a `GenServer`, an `Agent`, a `Task`, or any other `OTP`
behaviour that manages a process. Realistically you'll want a long lived process
to complement Oban's behaviour, which makes a `GenServer` or `GenStateMachine`
ideal.

Upon startup, Oban dynamically injects each plugin into its supervision tree and
passes a few base options along with any custom configuration for the plugin.

Every plugin receives these base options:

* `:conf` — An `Oban.Config` struct, which contains all of the options provided
  to `Oban.start_link/1` in a validated and normalized form.
* `:name` — A unique via tuple scoped to the current supervision tree. The name
  may be used later to support helper/interface functions.

## Example Plugin

Let's look at a tiny example plugin to get a feel for how options are passed in
and how they run. Our plugin will periodically generate a table of counts for
each `queue` / `state` combination and then print it out. It isn't an amazingly
useful plugin, but it demonstrates how to handle options, work with the
`Oban.Config` struct, and periodically interact with the `oban_jobs` table.

```elixir
defmodule MyApp.Plugins.Breakdown do
  use GenServer

  import Ecto.Query, only: [group_by: 3, select: 3]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    state = Map.new(opts)

    {:ok, schedule_poll(state)}
  end

  @impl GenServer
  def handle_info(:poll, %{conf: conf} = state) do
    breakdown =
      Oban.Repo.all(
        conf,
        Oban.Job
        |> group_by([j], [j.queue, j.state])
        |> select([j], {j.queue, j.state, count(j.id)})
      )

    IO.inspect(breakdown)

    {:noreply, schedule_poll(state)}
  end

  defp schedule_poll(%{interval: interval}) do
    Process.send_after(self(), :poll, interval)

    state
  end
end
```

The plugin's `start_link/1` function expects a keyword list with `:name`,
`:conf`, and `:interval` values. After extracting the `:name` for process
registration, it passes the options through to `init/1`. The `init` function
converts the keyword list of options into a map for easier access and then
begins a polling loop.

Each iteration of the loop will query the `oban_jobs` table and print out a list
of `{queue, state, count}` tuples like this:

```
[
  {"default", "executing", 8},
  {"default", "retryable", 1},
  {"default", "completed", 3114},
  {"default", "discarded", 1},
  {"events", "scheduled", 3},
  {"events", "executing", 21},
  {"events", "retryable", 2},
  {"events", "completed", 1783},
  {"events", "discarded", 1},
]
```

Now all that is left is to adding the `Breakdown` module to Oban's plugin list:

```elixir
config :my_app, Oban,
  plugins: [
    {MyApp.Plugins.Breakdown, interval: :timer.seconds(10)}
  ]
  ...
```

In the configuration we're only providing the `:interval` value. Oban injects
the `:name` and `:conf` automatically.

## Calling Interface Functions

Plugins are named dynamically using `via` tuples, which is an effective way to
manage process registration for multiple unique Oban instances. However, it
makes writing interface functions for plugins a little more complicated. The
solution is to make use of the `Oban.Registry` for process discovery.

Imagine adding a `pause` interface function to the `Breakdown` plugin we built
above:

```elixir
alias Oban.Registry

def pause(oban_name \\ Oban) do
  oban_name
  |> Registry.whereis({:plugin, __MODULE__})
  |> GenServer.call(:pause)
end
```

The function accepts an `oban_name` argument with a default of `Oban`, which is
the default name for an Oban supervision tree. It then calls `whereis/2` with a
`{:plugin, plugin_name}` tuple and uses the returned `pid` to call the plugin
process.

You can then call `pause/1` from elsewhere in the application:

```elixir
MyApp.Plugins.Breakdown.pause()

# or

MyApp.Plugins.Breakdown.pause(MyApp.OtherOban)
```

## Caveats

Plugins run directly within Oban's supervision tree. A badly behaving plugin,
e.g. a plugin that crashes repeatedly, may bring down the entire supervision
tree. Be sure that your plugin has safety mechanisms in place to prevent
repeated crashes during startup.
