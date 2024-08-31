defmodule Oban.Engines.Dolphin do
  @moduledoc """
  An engine for running Oban with MySQL (via the MyXQL adapter).

  ## Usage

  Start an `Oban` instance using the `Dolphin` engine:

      Oban.start_link(
        engine: Oban.Engines.Dolphin,
        queues: [default: 10],
        repo: MyApp.Repo
      )
  """

  @behaviour Oban.Engine
end
