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

    DeltaCrdt.add_neighbours(c1, [c1, c2, c3])
    DeltaCrdt.add_neighbours(c2, [c1, c2, c3])
    DeltaCrdt.add_neighbours(c3, [c1, c2, c3])
    [c1: c1, c2: c2, c3: c3]
  end

  test "works", context do
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "Kraan"])
    DeltaCrdt.mutate_async(context.c1, :add, [:Tonci, "Galic"])

    assert %{"Derek" => "Kraan", Tonci: "Galic"} == DeltaCrdt.read(context.c1)
  end

  test "garbage collection removes deltas", context do
    DeltaCrdt.mutate_async(context.c1, :add, ["Derek", "Kraan"])

    Process.sleep(60)

    assert %{"Derek" => "Kraan"} == DeltaCrdt.read(context.c2)
    assert %{"Derek" => "Kraan"} == DeltaCrdt.read(context.c3)

    GenServer.call(context.c1, :garbage_collect_deltas)
    GenServer.call(context.c2, :garbage_collect_deltas)
    GenServer.call(context.c3, :garbage_collect_deltas)

    assert 0 = GenServer.call(context.c1, :delta_count)
    assert 0 = GenServer.call(context.c2, :delta_count)
    assert 0 = GenServer.call(context.c3, :delta_count)
  end

  test "garbage collection works in case of just 1 node" do
    {:ok, c1} =
      DeltaCrdt.start_link(AWLWWMap, sync_interval: 5, ship_interval: 5, ship_debounce: 5)

    DeltaCrdt.add_neighbours(c1, [c1])

    DeltaCrdt.mutate_async(c1, :add, ["Derek", "Kraan"])
    GenServer.call(c1, :garbage_collect_deltas)
    assert 0 = GenServer.call(c1, :delta_count)
  end

  test "storage backend can store and retrieve state" do
    DeltaCrdt.start_link(AWLWWMap, [storage_module: MemoryStorage], name: :storage_test)

    DeltaCrdt.mutate(:storage_test, :add, ["Derek", "Kraan"])
    assert %{"Derek" => "Kraan"} = DeltaCrdt.read(:storage_test)
  end

  test "storage backend is used to rehydrate state after a crash" do
    task =
      Task.async(fn ->
        DeltaCrdt.start_link(AWLWWMap, [storage_module: MemoryStorage], name: :storage_test)
        DeltaCrdt.mutate(:storage_test, :add, ["Derek", "Kraan"])
      end)

    Task.await(task)

    DeltaCrdt.start_link(AWLWWMap, [storage_module: MemoryStorage], name: :storage_test)

    assert %{"Derek" => "Kraan"} = DeltaCrdt.read(:storage_test)
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

  test "can sync after network partition" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, ship_interval: 5, ship_debounce: 5)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, ship_interval: 5, ship_debounce: 5)
    DeltaCrdt.add_neighbours(c1, [c2])
    DeltaCrdt.add_neighbours(c2, [c1])
    DeltaCrdt.mutate(c1, :add, ["CRDT1", "represent"])
    DeltaCrdt.mutate(c2, :add, ["CRDT2", "also here"])
    Process.sleep(100)
    assert %{"CRDT1" => "represent", "CRDT2" => "also here"} = DeltaCrdt.read(c1)

    # uncouple them
    send(c1, :forget_neighbours)
    send(c2, :forget_neighbours)

    DeltaCrdt.mutate(c1, :add, ["CRDTa", "only present in 1"])
    DeltaCrdt.mutate(c1, :add, ["CRDTb", "only present in 1"])
    DeltaCrdt.mutate(c1, :remove, ["CRDT1"])

    Process.sleep(100)

    assert Map.has_key?(DeltaCrdt.read(c1), "CRDTa")
    refute Map.has_key?(DeltaCrdt.read(c2), "CRDTa")

    GenServer.call(c1, :garbage_collect_deltas)
    GenServer.call(c2, :garbage_collect_deltas)

    # make them neighbours again
    DeltaCrdt.add_neighbours(c1, [c2])
    DeltaCrdt.add_neighbours(c2, [c1])

    Process.sleep(1000)

    assert Map.has_key?(DeltaCrdt.read(c1), "CRDTa")
    refute Map.has_key?(DeltaCrdt.read(c1), "CRDT1")
    assert Map.has_key?(DeltaCrdt.read(c2), "CRDTa")
    refute Map.has_key?(DeltaCrdt.read(c2), "CRDT1")
  end
end
