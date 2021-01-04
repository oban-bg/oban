defmodule Oban.Plugins.CronTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Cron

  describe "validate/1" do
    test ":crontab is validated as a list of cron job expressions" do
      refute_valid(crontab: ["* * * * *"])
      refute_valid(crontab: [["* * * * *", Fake]])
      refute_valid(crontab: [Worker])

      assert_valid(crontab: [{"* * * * *", Worker}])
      assert_valid(crontab: [{"* * * * *", Worker, queue: "special"}])
    end

    test ":timezone is validated as a known timezone" do
      refute_valid(timezone: "")
      refute_valid(timezone: nil)
      refute_valid(timezone: "america")
      refute_valid(timezone: "america/chicago")

      assert_valid(timezone: "Etc/UTC")
      assert_valid(timezone: "Europe/Copenhagen")
      assert_valid(timezone: "America/Chicago")
    end
  end

  defp assert_valid(opts) do
    assert :ok = Cron.validate!(opts)
  end

  defp refute_valid(opts) do
    assert_raise ArgumentError, fn -> Cron.validate!(opts) end
  end
end
