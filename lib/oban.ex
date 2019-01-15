defmodule Oban do
  @moduledoc false

  # TODO: Documentation
  # TODO: Behaviour

  alias Oban.{Config, Job, Supervisor}

  @type job_opts :: map() | Keyword.t()
  @type conf :: Config.t()

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Oban

      @supervisor_name Module.concat(__MODULE__, "Supervisor")
      @config_name Module.concat(__MODULE__, "Config")
      @database_name Module.concat(__MODULE__, "Database")

      @opts unquote(opts)
            |> Keyword.put(:main, __MODULE__)
            |> Keyword.put(:name, @supervisor_name)
            |> Keyword.put(:config_name, @config_name)
            |> Keyword.put(:database_name, @database_name)

      @doc false
      def child_spec(opts) do
        %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
      end

      @impl Oban
      def start_link(opts \\ []) do
        @opts
        |> Keyword.merge(opts)
        |> Supervisor.start_link()
      end

      @impl Oban
      def push(job_opts) when is_list(job_opts) do
        job_opts
        |> Map.new()
        |> push()
      end

      def push(job_opts) when is_map(job_opts) do
        db_pid = Process.whereis(@database_name)
        cf_pid = Process.whereis(@config_name)

        %Config{database: database} = Config.get(cf_pid)

        database.push(db_pid, Job.new(job), conf)
      end
    end
  end
end
