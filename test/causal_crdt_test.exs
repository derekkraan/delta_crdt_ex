defmodule CausalCrdtTest do
  use ExUnit.Case, async: true
  doctest DeltaCrdt

  alias DeltaCrdt.AWLWWMap

  describe "with context" do
    setup do
      {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)

      {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)

      {:ok, c3} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)

      DeltaCrdt.set_neighbours(c1, [c1, c2, c3])
      DeltaCrdt.set_neighbours(c2, [c1, c2, c3])
      DeltaCrdt.set_neighbours(c3, [c1, c2, c3])
      [c1: c1, c2: c2, c3: c3]
    end

    test "basic test case", context do
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
      assert %{} == DeltaCrdt.read(context.c1)
      assert %{} == DeltaCrdt.read(context.c2)
    end
  end

  test "synchronization is directional, diffs are sent TO neighbours" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)
    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.mutate(c1, :add, ["Derek", "Kraan"])
    DeltaCrdt.mutate(c2, :add, ["Tonci", "Galic"])
    Process.sleep(100)
    assert %{"Derek" => "Kraan"} == DeltaCrdt.read(c1)
    assert %{"Derek" => "Kraan", "Tonci" => "Galic"} == DeltaCrdt.read(c2)
  end

  test "can sync to neighbours specified by name" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50, name: :neighbour_name_1)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50, name: :neighbour_name_2)
    DeltaCrdt.set_neighbours(c1, [:neighbour_name_2])
    DeltaCrdt.set_neighbours(c2, [{:neighbour_name_1, node()}])
    DeltaCrdt.mutate(c1, :add, ["Derek", "Kraan"])
    DeltaCrdt.mutate(c2, :add, ["Tonci", "Galic"])
    Process.sleep(100)
    assert %{"Derek" => "Kraan", "Tonci" => "Galic"} == DeltaCrdt.read(c1)
    assert %{"Derek" => "Kraan", "Tonci" => "Galic"} == DeltaCrdt.read(c2)
  end

  test "storage backend can store and retrieve state" do
    DeltaCrdt.start_link(AWLWWMap, storage_module: MemoryStorage, name: :storage_test)

    DeltaCrdt.mutate(:storage_test, :add, ["Derek", "Kraan"])
    assert %{"Derek" => "Kraan"} == DeltaCrdt.read(:storage_test)
  end

  test "storage backend is used to rehydrate state after a crash" do
    task =
      Task.async(fn ->
        DeltaCrdt.start_link(AWLWWMap, storage_module: MemoryStorage, name: :storage_test)
        DeltaCrdt.mutate(:storage_test, :add, ["Derek", "Kraan"])
      end)

    Task.await(task)

    # time for the previous process to deregister itself
    Process.sleep(10)

    {:ok, _} = DeltaCrdt.start_link(AWLWWMap, storage_module: MemoryStorage, name: :storage_test)

    assert %{"Derek" => "Kraan"} == DeltaCrdt.read(:storage_test)
  end

  test "syncs after adding neighbour" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)
    DeltaCrdt.mutate(c1, :add, ["CRDT1", "represent"])
    DeltaCrdt.mutate(c2, :add, ["CRDT2", "also here"])
    DeltaCrdt.set_neighbours(c1, [c2])
    Process.sleep(100)
    assert %{"CRDT1" => "represent"} == DeltaCrdt.read(c1)
    assert %{"CRDT1" => "represent", "CRDT2" => "also here"} == DeltaCrdt.read(c2)
  end

  test "can sync after network partition" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)

    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 50)

    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.set_neighbours(c2, [c1])

    DeltaCrdt.mutate(c1, :add, ["CRDT1", "represent"])

    DeltaCrdt.mutate(c2, :add, ["CRDT2", "also here"])

    Process.sleep(200)
    assert %{"CRDT1" => "represent", "CRDT2" => "also here"} == DeltaCrdt.read(c1)

    # uncouple them
    DeltaCrdt.set_neighbours(c1, [])
    DeltaCrdt.set_neighbours(c2, [])

    DeltaCrdt.mutate(c1, :add, ["CRDTa", "only present in 1"])
    DeltaCrdt.mutate(c1, :add, ["CRDTb", "only present in 1"])
    DeltaCrdt.mutate(c1, :remove, ["CRDT1"])

    Process.sleep(200)

    assert Map.has_key?(DeltaCrdt.read(c1), "CRDTa")
    refute Map.has_key?(DeltaCrdt.read(c2), "CRDTa")

    # make them neighbours again
    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.set_neighbours(c2, [c1])

    Process.sleep(200)

    assert Map.has_key?(DeltaCrdt.read(c1), "CRDTa")
    refute Map.has_key?(DeltaCrdt.read(c1), "CRDT1")
    assert Map.has_key?(DeltaCrdt.read(c2), "CRDTa")
    refute Map.has_key?(DeltaCrdt.read(c2), "CRDT1")
  end

  test "syncing when values happen to be the same" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 20)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 20)
    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.set_neighbours(c2, [c1])

    DeltaCrdt.mutate(c1, :add, ["key", "value"])
    DeltaCrdt.mutate(c2, :add, ["key", "value"])

    Process.sleep(50)

    DeltaCrdt.mutate(c1, :remove, ["key"])

    Process.sleep(50)

    refute Map.has_key?(DeltaCrdt.read(c1), "key")
    refute Map.has_key?(DeltaCrdt.read(c2), "key")
  end

  @tag :slow
  @tag timeout: 600_000
  test "adding a lot of entries" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 500)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 500)
    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.set_neighbours(c2, [c1])

    for key <- 1..100_000, do: DeltaCrdt.mutate(c1, :add, [key, %{}], 60_000)

    Process.sleep(60_000)

    assert map_size(DeltaCrdt.read(c1)) == 100_000
    assert map_size(DeltaCrdt.read(c2)) == 100_000
  end

  test "adding a neighbour with own entries to existing pair" do
    {:ok, c1} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 20)
    {:ok, c2} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 20)
    DeltaCrdt.set_neighbours(c1, [c2])
    DeltaCrdt.set_neighbours(c2, [c1])

    DeltaCrdt.mutate(c1, :add, ["step1", 1])

    Process.sleep(50)

    # Create a new neighbour that already has data:
    {:ok, c3} = DeltaCrdt.start_link(AWLWWMap, sync_interval: 20)
    DeltaCrdt.mutate(c3, :add, ["step2", 2])

    Process.sleep(50)

    # Connect them
    DeltaCrdt.set_neighbours(c3, [c1])
    DeltaCrdt.set_neighbours(c1, [c3])

    Process.sleep(50)

    expected = %{"step1" => 1, "step2" => 2}

    assert {DeltaCrdt.read(c1), DeltaCrdt.read(c2), DeltaCrdt.read(c3)} ==
             {expected, expected, expected}
  end
end
