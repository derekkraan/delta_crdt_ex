defmodule DeltaSubscriberTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DeltaCrdt.AWLWWMap

  test "receives deltas updates" do
    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 5,
        ship_interval: 5,
        ship_debounce: 5,
        subscribe_updates: {:crdt_updated, self()}
      )

    :ok = DeltaCrdt.mutate(c1, :add, ["Derek", "Kraan"])
    assert_received({:crdt_updated, [{:add, "Derek", "Kraan"}]})

    :ok = DeltaCrdt.mutate(c1, :add, ["Derek", "Kraan"])
    refute_received({:crdt_updated, [{:add, "Derek", "Kraan"}]})

    :ok = DeltaCrdt.mutate(c1, :add, ["Derek", nil])
    assert_received({:crdt_updated, [{:remove, "Derek"}]})
  end

  test "updates are bundled" do
    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 5,
        ship_interval: 5,
        ship_debounce: 5
      )

    {:ok, c2} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 5,
        ship_interval: 5,
        ship_debounce: 5,
        subscribe_updates: {:crdt_updated, self()}
      )

    :ok = DeltaCrdt.mutate(c1, :add, ["Derek", "Kraan"])
    :ok = DeltaCrdt.mutate(c1, :add, ["Andrew", "Kraan"])
    :ok = DeltaCrdt.mutate(c1, :add, ["Nathan", "Kraan"])

    DeltaCrdt.set_neighbours(c1, [c2])

    assert_receive({:crdt_updated, diff}, 100)

    assert Map.new(diff, fn {:add, k, v} -> {k, v} end) == %{
             "Derek" => "Kraan",
             "Andrew" => "Kraan",
             "Nathan" => "Kraan"
           }
  end

  property "add and remove operations result in correct map" do
    op =
      ExUnitProperties.gen all op <- StreamData.member_of([:add, :remove]),
                               key <- term(),
                               value <- term() do
        case op do
          :add -> {:add, key, value}
          :remove -> {:remove, key}
        end
      end

    check all ops <- list_of(op) do
      {:ok, c1} =
        DeltaCrdt.start_link(AWLWWMap,
          sync_interval: 5,
          ship_interval: 5,
          ship_debounce: 5,
          subscribe_updates: {:update, self()}
        )

      Enum.each(ops, fn
        {:add, k, v} ->
          DeltaCrdt.mutate(c1, :add, [k, v])

        {:remove, k} ->
          DeltaCrdt.mutate(c1, :remove, [k])
      end)

      out =
        Enum.reduce(ops, %{}, fn
          {:add, k, v}, map -> Map.put(map, k, v)
          {:remove, k}, map -> Map.delete(map, k)
        end)

      assert out == construct_map()
    end
  end

  defp construct_map(map \\ %{}) do
    receive do
      {:update, diffs} ->
        Enum.reduce(diffs, map, fn
          {:add, k, v}, map ->
            Map.put(map, k, v)

          {:remove, k}, map ->
            Map.delete(map, k)
        end)
        |> construct_map()
    after
      50 -> map
    end
  end
end
