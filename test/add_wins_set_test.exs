defmodule DeltaCrdt.AddWinsSetTest do
  use ExUnit.Case, async: true

  test "with running CRDTs" do
    crdt = %DeltaCrdt.AddWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt3} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt1, {:add_neighbour, crdt3})
    send(crdt2, {:add_neighbour, crdt1})
    send(crdt2, {:add_neighbour, crdt3})
    send(crdt3, {:add_neighbour, crdt1})
    send(crdt3, {:add_neighbour, crdt2})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})

    assert ["a"] == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})

    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert ["a"] == GenServer.call(crdt2, {:read, DeltaCrdt.AddWinsSet})
    assert ["a"] == GenServer.call(crdt3, {:read, DeltaCrdt.AddWinsSet})

    GenServer.cast(crdt2, {:operation, {DeltaCrdt.AddWinsSet, :remove, ["a"]}})
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert [] == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})
    assert [] == GenServer.call(crdt2, {:read, DeltaCrdt.AddWinsSet})
    assert [] == GenServer.call(crdt3, {:read, DeltaCrdt.AddWinsSet})
  end

  test "can add an element" do
    crdt = %DeltaCrdt.AddWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["b"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["c"]}})
    assert ["a", "b", "c"] == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})
  end

  test "can remove an element" do
    crdt = %DeltaCrdt.AddWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["b"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["c"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :remove, ["b"]}})
    assert ["a", "c"] == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})
  end

  test "can clear the set" do
    crdt = %DeltaCrdt.AddWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["b"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :clear, []}})
    assert [] == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})
  end

  test "handles conflicts" do
    crdt = %DeltaCrdt.AddWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt3} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt1, {:add_neighbour, crdt3})
    send(crdt2, {:add_neighbour, crdt1})
    send(crdt2, {:add_neighbour, crdt3})
    send(crdt3, {:add_neighbour, crdt1})
    send(crdt3, {:add_neighbour, crdt2})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})
    GenServer.cast(crdt2, {:operation, {DeltaCrdt.AddWinsSet, :add, ["b"]}})
    GenServer.cast(crdt3, {:operation, {DeltaCrdt.AddWinsSet, :add, ["c"]}})
    send(crdt1, :ship_interval_or_state_to_all)
    send(crdt2, :ship_interval_or_state_to_all)
    send(crdt3, :ship_interval_or_state_to_all)
    Process.sleep(10)
    assert ~w(a b c) == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})
  end

  test "add wins" do
    crdt = %DeltaCrdt.AddWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt2, {:add_neighbour, crdt1})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})
    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.AddWinsSet, :add, ["a"]}})
    GenServer.cast(crdt2, {:operation, {DeltaCrdt.AddWinsSet, :remove, ["a"]}})
    send(crdt1, :ship_interval_or_state_to_all)
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)
    assert ~w(a) == GenServer.call(crdt1, {:read, DeltaCrdt.AddWinsSet})
  end
end
