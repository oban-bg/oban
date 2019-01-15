defmodule Oban.Database do
  @moduledoc """
  The Database behaviour specifies how workers can push, pull and otherwise interact with
  persistent storage.
  """

  alias Oban.{Config, Job}

  @type db :: GenServer.server()
  @type id :: binary() | integer()
  @type cursor :: id() | :ets.continuation()
  @type conf :: Config.t()
  @type queue :: binary()
  @type count :: pos_integer()
  @type info_mode :: :all | :processes | :queues | :stats

  @doc """
  Start a new database process linked to the calling process.
  """
  @callback start_link(opts :: Keyword.t()) :: GenServer.on_start()

  @doc """
  Push a job into the database for asynchronous processing.

  If storage is successful then the list of jobs will be returned with the `id` assigned by the
  database and optional metadata additions.
  """
  @callback push(db(), Job.t(), conf()) :: Job.t()

  @doc """
  Pull one or more jobs from the database for processing.

  This is a blocking operation that will either return a list of raw job data or the atom
  `:timeout`, indicating that no jobs were available within the blocking period. It is essential
  that jobs remain in the database until they are acknowledged through `ack/2`.
  """
  @callback pull(db(), queue(), count(), conf()) :: [Job.t()]

  @doc """
  Check what is coming up in the queue without pulling anything out.

  Peeking can be done in chunks, where the `count` limits the number of entries returned per call
  and the `id` is a cursor used for pagination.

  The function returns a tuple with the last matched id and a list of jobs. The id may be used to
  continue pagination.
  """
  @callback peek(db(), queue(), count(), nil | cursor(), conf()) :: {[Job.t()], cursor()} | []

  @doc """
  Acknowledge that a job has been processed successfully.

  This call ensures that a job won't be processed again. It is a safeguard against data loss if
  the server is terminated during processing or there are unexpected errors. All jobs should be
  acknowledged, regardless of whether they succeeded or failed.

  The return value is `true` if the job was acknowledged, or `false` if it wasn't.
  """
  @callback ack(db(), queue(), id(), conf()) :: boolean()

  @doc """
  Restore a pending job back into its queue for processing.

  If a job is consumed from the queue via `pull/4`, but it is never acknowledged via `ack/4` it
  will be stuck in a pending state. Calling `restore/4` will push a pending job back to its
  original queue.

  The return value is `true` if the job was restored, `false` if it wasn't.
  """
  @callback restore(db(), queue(), id(), conf()) :: boolean()

  @doc """
  Purge all queues, stats and other data associated with this database instance.
  """
  @callback clear(db(), conf()) :: :ok
end
