defmodule DotPruningTest do
  use ExUnit.Case, async: true

  alias DeltaCrdt.AWLWWMap

  @grace 100
  @sync 20

  defp start(opts \\ []) do
    {:ok, crdt} =
      DeltaCrdt.start_link(
        AWLWWMap,
        Keyword.merge([sync_interval: @sync, prune_dots_after: @grace], opts)
      )

    crdt
  end

  defp connect(crdts), do: Enum.each(crdts, &DeltaCrdt.set_neighbours(&1, crdts))

  defp node_id(crdt), do: :sys.get_state(crdt).node_id
  defp dot_ids(crdt), do: :sys.get_state(crdt).crdt_state.dots |> Map.keys() |> MapSet.new()

  defp stop(crdt) do
    ref = Process.monitor(crdt)
    Process.unlink(crdt)
    Process.exit(crdt, :kill)
    assert_receive {:DOWN, ^ref, _, _, _}
  end

  defp wait_for_prune, do: Process.sleep(@grace * 3)

  test "drops the dots of a stopped replica once no value references them" do
    c1 = start()
    c2 = start()
    connect([c1, c2])

    DeltaCrdt.put(c2, :member, "c2")
    Process.sleep(@sync * 5)
    dead_id = node_id(c2)
    assert dead_id in dot_ids(c1)

    stop(c2)
    DeltaCrdt.delete(c1, :member)
    wait_for_prune()

    refute dead_id in dot_ids(c1)
  end

  test "keeps the dots of a stopped replica while a value still references them" do
    c1 = start()
    c2 = start()
    connect([c1, c2])

    DeltaCrdt.put(c2, :member, "c2")
    Process.sleep(@sync * 5)
    dead_id = node_id(c2)

    stop(c2)
    wait_for_prune()

    assert dead_id in dot_ids(c1)
    assert %{member: "c2"} == DeltaCrdt.to_map(c1)
  end

  test "never drops its own dots, so new writes still reach peers" do
    c1 = start()
    c2 = start()
    connect([c1, c2])

    DeltaCrdt.put(c1, :a, 1)
    DeltaCrdt.delete(c1, :a)
    wait_for_prune()

    assert node_id(c1) in dot_ids(c1)

    DeltaCrdt.put(c1, :b, 2)
    Process.sleep(@sync * 5)
    assert %{b: 2} == DeltaCrdt.to_map(c2)
  end

  test "removed keys stay removed after their dots are pruned" do
    c1 = start()
    c2 = start()
    c3 = start()
    connect([c1, c2, c3])

    DeltaCrdt.put(c3, :member, "c3")
    Process.sleep(@sync * 5)
    stop(c3)
    connect([c1, c2])

    DeltaCrdt.delete(c1, :member)
    wait_for_prune()
    DeltaCrdt.put(c2, :other, 1)
    Process.sleep(@sync * 5)

    assert %{other: 1} == DeltaCrdt.to_map(c1)
    assert %{other: 1} == DeltaCrdt.to_map(c2)
  end

  test "prunes again once the last replica that re-sends a dead id is gone" do
    c1 = start()
    legacy = start(prune_dots_after: :infinity)
    c3 = start()
    connect([c1, legacy, c3])

    DeltaCrdt.put(c3, :member, "c3")
    Process.sleep(@sync * 5)
    dead_id = node_id(c3)
    stop(c3)
    connect([c1, legacy])
    DeltaCrdt.delete(c1, :member)
    wait_for_prune()

    assert dead_id in dot_ids(legacy)

    stop(legacy)
    wait_for_prune()

    refute dead_id in dot_ids(c1)
  end

  test "keeps every dot when pruning is disabled" do
    c1 = start(prune_dots_after: :infinity)
    c2 = start(prune_dots_after: :infinity)
    connect([c1, c2])

    DeltaCrdt.put(c2, :member, "c2")
    Process.sleep(@sync * 5)
    dead_id = node_id(c2)

    stop(c2)
    DeltaCrdt.delete(c1, :member)
    wait_for_prune()

    assert dead_id in dot_ids(c1)
  end
end
