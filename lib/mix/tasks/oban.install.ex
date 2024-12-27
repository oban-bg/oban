defmodule Mix.Tasks.Oban.Install.Docs do
  @moduledoc false

  def short_doc do
    "Install and configure Oban for use in an application."
  end

  def example do
    "mix oban.install"
  end

  def long_doc do
    """
    Install and configure Oban for use in an application.

    ## Example

    Install using the default Ecto repo and matching engine:

    ```bash
    mix oban.install
    ```

    Specify a `SQLite3` repo and `Lite` engine explicitly:

    ```bash
    mix oban.install --repo MyApp.LiteRepo --engine Oban.Engines.Lite
    ```

    ## Options

    * `--engine` or `-e` — Select the engine for your repo, defaults to `Oban.Engines.Postgres`
    * `--notifier` or `-n` — Select the pubsub notifier, defaults to `Oban.Notifiers.Postgres`
    * `--repo` or `-r` — Specify an Ecto repo for Oban to use
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Oban.Install do
    @shortdoc __MODULE__.Docs.short_doc()

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :oban,
        adds_deps: [:oban],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: [],
        schema: [engine: :string, notifier: :string, repo: :string],
        defaults: [],
        aliases: [e: :engine, n: :notifier, r: :repo],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      opts = igniter.args.options

      case extract_repo(igniter, app_name, opts[:repo]) do
        {nil, igniter} ->
          igniter

        {repo, igniter} ->
          engine = parse_engine(repo, opts[:engine])
          notifier = parse_notifier(repo, opts[:notifier])

          conf_code = [engine: engine, notifier: notifier, queues: [default: 10], repo: repo]
          test_code = [testing: :manual]
          tree_code = "Application.fetch_env!(#{app_name}, Oban)"

          migration = """
          use Ecto.Migration

          def up, do: Oban.Migration.up()

          def down, do: Oban.Migration.down(version: 1)
          """

          igniter
          |> Igniter.Project.Deps.add_dep({:oban, "~> 2.18"})
          |> Igniter.Project.Config.configure("config.exs", app_name, [Oban], {:code, conf_code})
          |> Igniter.Project.Config.configure("test.exs", app_name, [Oban], {:code, test_code})
          |> Igniter.Project.Application.add_new_child({Oban, {:code, tree_code}}, after: repo)
          |> Igniter.Project.Formatter.import_dep(:oban)
          |> Igniter.Libs.Ecto.gen_migration(repo, "add_oban", body: migration)
      end
    end

    defp extract_repo(igniter, app_name, nil) do
      case Application.get_env(app_name, :ecto_repos, []) do
        [repo | _] ->
          {repo, igniter}

        _ ->
          {nil, Igniter.add_issue(igniter, "No ecto repos found for #{inspect(app_name)}")}
      end
    end

    defp extract_repo(igniter, _app_name, module) do
      repo = Igniter.Project.Module.parse(module)

      case Igniter.Project.Module.module_exists(igniter, repo) do
        {true, igniter} ->
          {repo, igniter}

        {_boo, igniter} ->
          {nil, Igniter.add_issue(igniter, "The provided repo (#{inspect(repo)}) doesn't exist")}
      end
    end

    defp parse_engine(repo, nil) do
      case repo.__adapter__() do
        Ecto.Adapters.Postgres -> Oban.Engines.Basic
        Ecto.Adapters.MyXQL -> Oban.Engines.Dolphin
        Ecto.Adapters.SQLite3 -> Oban.Engines.Lite
      end
    end

    defp parse_engine(_repo, module), do: Igniter.Project.Module.parse(module)

    defp parse_notifier(repo, nil) do
      case repo.__adapter__() do
        Ecto.Adapters.Postgres -> Oban.Notifiers.Postgres
        _ -> Oban.Notifiers.PG
      end
    end

    defp parse_notifier(_repo, module), do: Igniter.Project.Module.parse(module)
  end
else
  defmodule Mix.Tasks.Oban.Install do
    @shortdoc "Install `igniter` in order to install Oban."

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'oban.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
