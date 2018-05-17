defmodule DeltaCrdt.AddWinsFirstWriteWinsMapTest do
  use ExUnit.Case, async: true

  test "can add elements to the map" do
    crdt = %DeltaCrdt.ObservedRemoveMap{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 1]}}
    )

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Tonci", 2]}}
    )

    assert %{"Derek" => 1, "Tonci" => 2} ==
             GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsFirstWriteWinsMap})
  end

  test "can remove elements from the map" do
    crdt = %DeltaCrdt.ObservedRemoveMap{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 1]}}
    )

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Tonci", 2]}}
    )

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :remove, ["Tonci"]}}
    )

    assert %{"Derek" => 1} == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsFirstWriteWinsMap})
  end

  test "add wins" do
    crdt = %DeltaCrdt.ObservedRemoveMap{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 1]}}
    )

    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 2]}}
    )

    GenServer.cast(
      crdt2,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :remove, ["Derek"]}}
    )

    send(crdt1, :ship_interval_or_state_to_all)
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert %{"Derek" => 2} == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsFirstWriteWinsMap})
  end

  test "first write wins" do
    crdt = %DeltaCrdt.ObservedRemoveMap{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 1]}}
    )

    GenServer.cast(
      crdt2,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 2]}}
    )

    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert %{"Derek" => 1} == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsFirstWriteWinsMap})
  end

  test "can overwrite value" do
    crdt = %DeltaCrdt.ObservedRemoveMap{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 1]}}
    )

    GenServer.cast(
      crdt1,
      {:operation, {DeltaCrdt.AddWinsFirstWriteWinsMap, :add, ["Derek", 2]}}
    )

    assert %{"Derek" => 2} == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsFirstWriteWinsMap})
  end

  test "CRDTs converge" do
    alias DeltaCrdt.{ObservedRemoveMap, CausalCrdt, AddWinsFirstWriteWinsMap}
    crdt = %ObservedRemoveMap{}
    {:ok, crdt1} = CausalCrdt.start_link(crdt)
    {:ok, crdt2} = CausalCrdt.start_link(crdt)
    {:ok, crdt3} = CausalCrdt.start_link(crdt)
    {:ok, crdt4} = CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbours, [crdt2, crdt3, crdt4]})
    send(crdt2, {:add_neighbours, [crdt1, crdt3, crdt4]})
    send(crdt3, {:add_neighbours, [crdt1, crdt2, crdt4]})
    send(crdt4, {:add_neighbours, [crdt1, crdt2, crdt3]})

    GenServer.call(crdt1, {:operation, {AddWinsFirstWriteWinsMap, :add, ["Derek", "Kraan"]}})

    GenServer.call(crdt1, {:operation, {AddWinsFirstWriteWinsMap, :add, ["Tonci", "Galic"]}})

    GenServer.call(crdt2, {:operation, {AddWinsFirstWriteWinsMap, :add, ["Tom", "Hoenderdos"]}})

    GenServer.call(crdt2, {:operation, {AddWinsFirstWriteWinsMap, :add, ["Koen", "Kuit"]}})

    GenServer.call(crdt3, {:operation, {AddWinsFirstWriteWinsMap, :add, ["Sanne", "Kalkman"]}})

    GenServer.call(crdt3, {:operation, {AddWinsFirstWriteWinsMap, :add, ["IJzer", "IJzer"]}})

    Process.sleep(300)

    assert 6 = GenServer.call(crdt1, {:read, AddWinsFirstWriteWinsMap}) |> Enum.count()
  end
end
