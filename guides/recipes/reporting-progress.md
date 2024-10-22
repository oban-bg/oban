# Reporting Job Progress

Most applications provide some way to generate an artifact—something that may
take the server a long time to accomplish. If it takes several minutes to render
a video, crunch some numbers or generate an export, users may be left wondering
whether your application is working. Providing periodic updates to end users
assures them that the work is being done and keeps the application feeling
responsive.

Reporting progress is something that any background job processor with
_unlimited execution time_ can do! Naturally, we'll look at an example built on
Oban.

## Use Case: Exporting a Large Zip File

Users of our site can export a zip of all the files they have uploaded. A _zip_
file (no, not a tar, our users don't have neck-beards) is generated on the fly,
when the user requests it. Lazily generating archives is great for our server's
utilization, but it means that users may wait a while when there are many files.
Fortunately, we know how many files will be included in the zip and we can use
that information to send progress reports! We will compute the archive's percent
complete as each file is added and push a message to the user.

### Before We Start

In the [forum question that prompted this guide][guide] the work was done
externally by a port process. Working with ports is well outside the scope of
this guide, so I've modified it for the sake of simplicity. The result is
slightly contrived as it puts both processes within the same module, which isn't
necessary if the only goal is to broadcast progress. This guide is ultimately
about coordinating processes to report progress from a background job, so that's
what we'll focus on (everything else will be rather [hand-wavy][wavy]).

## Coordinating Processes

Our worker, the creatively titled `ZippingWorker`, handles both building the
archive and reporting progress to the client. Showing the entire module at once
felt distracting, so we'll start with only the module definition and the
`perform/1` function:

```elixir
defmodule MyApp.Workers.ZippingWorker do
  use Oban.Worker, queue: :exports, max_attempts: 1

  alias MyApp.{Endpoint, Zipper}

  def perform(%_{args: %{"channel" => channel, "paths" => paths}}) do
    build_zip(paths)
    await_zip(channel)
  end

  # ...
end
```

The function accepts an Oban Job with a channel name and a list of file paths,
which it immediately passes on to the private `build_zip/1`:

```elixir
  defp build_zip(paths) do
    job_pid = self()

    Task.async(fn ->
      zip_path = Zipper.new()

      paths
      |> Enum.with_index(1)
      |> Enum.each(fn {path, index} ->
        :ok = Zipper.add_file(zip_path, path)
        send(job_pid, {:progress, trunc(index / length(paths) * 100)})
      end)

      send(job_pid, {:complete, zip_path})
    end)
  end
```

The function grabs the current pid, which belongs to the job, and kicks off an
asynchronous task to handle the zipping. With a few calls to a fictional
`Zipper` module the task works through each file path, adding it to the zip.
After adding a file the task sends a `:progress` message with the percent
complete back to the job. Finally, when the zip finishes, the task sends a
`:complete` message with a path to the archive.

The asynchronous call spawns a separate process and returns immediately. In
order for the task to finish building the zip we need to wait on it. Typically
we'd use `Task.await/2`, but we'll use a custom receive loop to track the task's
progress:

```elixir
  defp await_zip(channel) do
    receive do
      {:progress, percent} ->
        Endpoint.broadcast(channel, "zip:progress", percent)
        await_zip(channel)

      {:complete, zip_path} ->
        Endpoint.broadcast(channel, "zip:complete", zip_path)
    after
      30_000 ->
        Endpoint.broadcast(channel, "zip:failed", "zipping failed")
        raise RuntimeError, "no progress after 30s"
    end
  end
```

The receive loop blocks execution while it waits for `:progress` or `:complete`
messages. When a message comes in it broadcasts to the provided channel and the
client receives an update (this example uses [Phoenix Channels][chan], but any
other PubSub type mechanism would work). As a safety mechanism we have an
`after` clause that will timeout after 30 seconds of inactivity. If the receive
block times out we notify the client and raise an error, failing the job.

## Made Possible by Unlimited Execution

Reporting progress asynchronously works in Oban because anything that blocks a
worker's `perform/1` function will keep the job executing. Jobs aren't executed
inside of a transaction, which alleviates any limitations on how long a job can
run.

This technique is suitable for any _single_ long running job where an end user
is waiting on the results. Consider using [Oban Pro's Batch][batch] jobs if you
need to combine _multiple_ jobs into a single output.

[guide]: https://elixirforum.com/t/oban-reliable-and-observable-job-processing/22449/52
[chan]: https://hexdocs.pm/phoenix/channels.html#content
[wavy]: https://www.quora.com/When-someone-says-this-explanation-was-hand-wavy-what-does-that-mean
[batch]: https://oban.pro/docs/pro/Oban.Pro.Batch.html
