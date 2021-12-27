defmodule Oban.NotifierTest do
  use Oban.Case

  alias Oban.Notifier

  describe "listen/notify" do
    test "notifying with complex types" do
      name = start_supervised_oban!(queues: [])

      Notifier.listen(name, [:signal])

      Notifier.notify(name, :signal, %{
        date: ~D[2021-08-09],
        keyword: [a: 1, b: 1],
        map: %{tuple: {1, :second}},
        tuple: {1, :second}
      })

      assert_receive {:notification, :signal, notice}
      assert %{"date" => "2021-08-09", "keyword" => [["a", 1], ["b", 1]]} = notice
      assert %{"map" => %{"tuple" => [1, "second"]}, "tuple" => [1, "second"]} = notice

      stop_supervised(name)
    end
  end
end
