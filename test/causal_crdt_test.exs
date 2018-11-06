defmodule CausalCrdtTest do
  use ExUnit.Case, async: true
  doctest DeltaCrdt

  alias DeltaCrdt.AWLWWMap

  setup do
    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    {:ok, c2} =
      DeltaCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    {:ok, c3} =
      DeltaCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    DeltaCrdt.add_neighbours(c1, [c2, c3])
    DeltaCrdt.add_neighbours(c2, [c1, c3])
    DeltaCrdt.add_neighbours(c3, [c2, c1])
    [c1: c1, c2: c2, c3: c3]
  end

  test "works", context do
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "Kraan"])
    DeltaCrdt.mutate_async(context.c1, :add, [:Tonci, "Galic"])

    assert %{"Derek" => "Kraan", Tonci: "Galic"} == DeltaCrdt.read(context.c1)
  end

  test "conflicting updates resolve", context do
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "one_wins"])
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "two_wins"])
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "three_wins"])
    Process.sleep(100)
    assert %{"Derek" => "three_wins"} == DeltaCrdt.read(context.c1)
    assert %{"Derek" => "three_wins"} == DeltaCrdt.read(context.c2)
    assert %{"Derek" => "three_wins"} == DeltaCrdt.read(context.c3)
  end

  test "add wins", context do
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "add_wins"])
    DeltaCrdt.mutate_async(context.c2, :remove, ["Derek"])
    Process.sleep(100)
    assert %{"Derek" => "add_wins"} == DeltaCrdt.read(context.c1)
    assert %{"Derek" => "add_wins"} == DeltaCrdt.read(context.c2)
  end

  test "can remove", context do
    DeltaCrdt.mutate(context.c1, :add, ["Derek", "add_wins"])
    Process.sleep(100)
    assert %{"Derek" => "add_wins"} == DeltaCrdt.read(context.c2)
    DeltaCrdt.mutate(context.c1, :remove, ["Derek"])
    Process.sleep(100)
    assert %{} == DeltaCrdt.read(context.c2)
    assert %{} == DeltaCrdt.read(context.c1)
  end

  test "syncs after adding neighbour" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, ship_interval: 5, ship_debounce: 5)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, ship_interval: 5, ship_debounce: 5)
    DeltaCrdt.mutate(c1, :add, ["CRDT1", "represent"])
    DeltaCrdt.mutate(c2, :add, ["CRDT2", "also here"])
    DeltaCrdt.add_neighbours(c1, [c2])
    Process.sleep(100)
    assert %{} = DeltaCrdt.read(c1)
  end
end
