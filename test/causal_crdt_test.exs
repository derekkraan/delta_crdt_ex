defmodule CausalCrdtTest do
  use ExUnit.Case, async: true

  alias DeltaCrdt.{CausalCrdt, AWLWWMap}

  setup do
    {:ok, c1} =
      CausalCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    {:ok, c2} =
      CausalCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    {:ok, c3} =
      CausalCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    send(c1, {:add_neighbours, [c2, c3]})
    send(c2, {:add_neighbours, [c1, c3]})
    send(c3, {:add_neighbours, [c2, c1]})
    [c1: c1, c2: c2, c3: c3]
  end

  test "works", context do
    GenServer.cast(context.c1, {:operation, {:add, ["Derek", "Kraan"]}})
    GenServer.cast(context.c1, {:operation, {:add, [:Tonci, "Galic"]}})

    assert %{"Derek" => "Kraan", Tonci: "Galic"} == CausalCrdt.read(context.c1)
  end

  test "conflicting updates resolve", context do
    GenServer.cast(context.c1, {:operation, {:add, ["Derek", "one_wins"]}})
    GenServer.cast(context.c2, {:operation, {:add, ["Derek", "two_wins"]}})
    GenServer.cast(context.c3, {:operation, {:add, ["Derek", "three_wins"]}})
    Process.sleep(100)
    assert %{"Derek" => "three_wins"} == CausalCrdt.read(context.c1)
    assert %{"Derek" => "three_wins"} == CausalCrdt.read(context.c2)
    assert %{"Derek" => "three_wins"} == CausalCrdt.read(context.c3)
  end

  test "add wins", context do
    GenServer.cast(context.c1, {:operation, {:add, ["Derek", "add_wins"]}})
    GenServer.cast(context.c2, {:operation, {:remove, ["Derek"]}})
    Process.sleep(100)
    assert %{"Derek" => "add_wins"} == CausalCrdt.read(context.c1)
    assert %{"Derek" => "add_wins"} == CausalCrdt.read(context.c2)
  end

  test "can remove", context do
    GenServer.call(context.c1, {:operation, {:add, ["Derek", "add_wins"]}})
    Process.sleep(100)
    assert %{"Derek" => "add_wins"} == CausalCrdt.read(context.c2)
    GenServer.call(context.c2, {:operation, {:remove, ["Derek"]}})
    Process.sleep(100)
    assert %{} == CausalCrdt.read(context.c2)
    assert %{} == CausalCrdt.read(context.c1)
  end

  test "syncs after adding neighbour" do
    {:ok, c1} = CausalCrdt.start_link(AWLWWMap, ship_interval: 5, ship_debounce: 5)
    {:ok, c2} = CausalCrdt.start_link(AWLWWMap, ship_interval: 5, ship_debounce: 5)
    GenServer.call(c1, {:operation, {:add, ["CRDT1", "represent"]}})
    GenServer.call(c2, {:operation, {:add, ["CRDT2", "also here"]}})
    send(c1, {:add_neighbours, [c2]})
    Process.sleep(100)
    assert %{} = CausalCrdt.read(c1)
  end
end
