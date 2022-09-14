if function_exported?(Code, :put_compiler_option, 2) do
  Code.put_compiler_option(:warnings_as_errors, true)
end

Oban.Test.Repo.start_link()
Oban.Test.UnboxedRepo.start_link()
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Oban.Test.Repo, :manual)
