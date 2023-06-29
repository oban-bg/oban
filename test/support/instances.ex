defmodule Oban.Test.MyOban do
  @moduledoc false

  use Oban, otp_app: :oban, repo: Oban.Test.Repo
end
