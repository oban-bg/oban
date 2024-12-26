defmodule Mix.Tasks.Oban.Install.Docs do
  @moduledoc false

  def short_doc do
    "Install Oban into the application"
  end

  def example do
    "mix oban.install --repo MyApp.Repo"
  end

  def long_doc do
    """
    Install and configure Oban for use in an application.

    ## Example

    ```bash
    #{example()}
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
    @moduledoc __MODULE__.Docs.long_doc()

    @shortdoc __MODULE__.Docs.short_doc()

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
        defaults: [engine: "Oban.Engines.Basic", notifier: "Oban.Notifiers.Postgres"],
        aliases: [engine: :e, notifier: :n, repo: :r],
        required: [:repo]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)

      opts = igniter.args.options
      engine = Igniter.Project.Module.parse(opts[:engine])
      notifier = Igniter.Project.Module.parse(opts[:notifier])
      repo = Igniter.Project.Module.parse(opts[:repo])

      conf_code = [engine: engine, notifier: notifier, queues: [default: 10], repo: repo]
      test_code = [testing: :manual]
      tree_code = "Application.fetch_env!(#{app_name}, Oban)"

      migration = """
      use Ecto.Migration

      def up, do: Oban.Migration.up(version: 12)

      def down, do: Oban.Migration.down(version: 1)
      """

      igniter
      |> ensure_repo_exists(repo)
      |> Igniter.Project.Deps.add_dep({:oban, "~> 2.18"})
      |> Igniter.Project.Config.configure("config.exs", app_name, [Oban], {:code, conf_code})
      |> Igniter.Project.Config.configure("test.exs", app_name, [Oban], {:code, test_code})
      |> Igniter.Project.Application.add_new_child({Oban, {:code, tree_code}}, after: repo)
      |> Igniter.Project.Formatter.import_dep(:oban)
      |> Igniter.Libs.Ecto.gen_migration(repo, "add_oban", body: migration)
    end

    defp ensure_repo_exists(igniter, repo) do
      case Igniter.Project.Module.module_exists(igniter, repo) do
        {true, igniter} ->
          igniter

        {_boo, igniter} ->
          Igniter.add_issue(igniter, "The provided repo (#{inspect(repo)}) doesn't exist")
      end
    end
  end
else
  defmodule Mix.Tasks.Oban.Install do
    @moduledoc __MODULE__.Docs.long_doc()

    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

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
