defmodule DeltaSubscriberTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DeltaCrdt.AWLWWMap

  def on_diffs(test_pid, diffs) do
    send(test_pid, {:diff, diffs})
  end

  test "receives deltas updates with MFA" do
    test_pid = self()

    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 50,
        on_diffs: {DeltaSubscriberTest, :on_diffs, [test_pid]}
      )

    ^c1 = DeltaCrdt.put(c1, "Derek", "Kraan")
    assert_received({:diff, [{:add, "Derek", "Kraan"}]})

    ^c1 = DeltaCrdt.put(c1, "Derek", "Kraan")
    refute_received({:diff, [{:add, "Derek", "Kraan"}]})

    ^c1 = DeltaCrdt.put(c1, "Derek", nil)
    assert_received({:diff, [{:remove, "Derek"}]})
  end

  test "receives deltas updates with function" do
    test_pid = self()

    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 50,
        on_diffs: fn diffs -> send(test_pid, {:diff, diffs}) end
      )

    ^c1 = DeltaCrdt.put(c1, "Derek", "Kraan")
    assert_received({:diff, [{:add, "Derek", "Kraan"}]})

    ^c1 = DeltaCrdt.put(c1, "Derek", "Kraan")
    refute_received({:diff, [{:add, "Derek", "Kraan"}]})

    ^c1 = DeltaCrdt.put(c1, "Derek", nil)
    assert_received({:diff, [{:remove, "Derek"}]})
  end

  test "updates are bundled" do
    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 50
      )

    test_pid = self()

    {:ok, c2} =
      DeltaCrdt.start_link(AWLWWMap,
        sync_interval: 50,
        on_diffs: {DeltaSubscriberTest, :on_diffs, [test_pid]}
      )

    ^c1 = DeltaCrdt.put(c1, "Derek", "Kraan")
    ^c1 = DeltaCrdt.put(c1, "Andrew", "Kraan")
    ^c1 = DeltaCrdt.put(c1, "Nathan", "Kraan")

    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.set_neighbours(c2, [c1])

    assert_receive({:diff, diff}, 100)

    assert Map.new(diff, fn {:add, k, v} -> {k, v} end) == %{
             "Derek" => "Kraan",
             "Andrew" => "Kraan",
             "Nathan" => "Kraan"
           }
  end

  property "add and remove operations result in correct map" do
    op =
      ExUnitProperties.gen all(
                             op <- StreamData.member_of([:add, :remove]),
                             key <- term(),
                             value <- term()
                           ) do
        case op do
          :add -> {:add, key, value}
          :remove -> {:remove, key}
        end
      end

    check all(ops <- list_of(op)) do
      test_pid = self()

      {:ok, c1} =
        DeltaCrdt.start_link(AWLWWMap,
          sync_interval: 50,
          on_diffs: {DeltaSubscriberTest, :on_diffs, [test_pid]}
        )

      Enum.each(ops, fn
        {:add, k, v} ->
          DeltaCrdt.put(c1, k, v)

        {:remove, k} ->
          DeltaCrdt.delete(c1, k)
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
      {:diff, diffs} ->
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
