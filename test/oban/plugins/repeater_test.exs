defmodule Oban.Plugins.RepeaterTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

  test "ignoring plugin startup" do
    logged =
      capture_log(fn ->
        start_supervised_oban!(plugins: [Oban.Plugins.Repeater])
      end)

    assert logged =~ "Repeater is deprecated"
  end
end
