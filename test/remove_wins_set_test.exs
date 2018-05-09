defmodule DeltaCrdt.RemoveWinsSetTest do
  use ExUnit.Case, async: true

  test "with running CRDTs" do
    crdt = %DeltaCrdt.RemoveWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt3} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt1, {:add_neighbour, crdt3})
    send(crdt2, {:add_neighbour, crdt1})
    send(crdt2, {:add_neighbour, crdt3})
    send(crdt3, {:add_neighbour, crdt1})
    send(crdt3, {:add_neighbour, crdt2})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})

    assert ["a"] == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})

    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert ["a"] == GenServer.call(crdt2, {:read, DeltaCrdt.RemoveWinsSet})
    assert ["a"] == GenServer.call(crdt3, {:read, DeltaCrdt.RemoveWinsSet})

    GenServer.cast(crdt2, {:operation, {DeltaCrdt.RemoveWinsSet, :remove, ["a"]}})
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert [] == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})
    assert [] == GenServer.call(crdt2, {:read, DeltaCrdt.RemoveWinsSet})
    assert [] == GenServer.call(crdt3, {:read, DeltaCrdt.RemoveWinsSet})
  end

  test "can add an element" do
    crdt = %DeltaCrdt.RemoveWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["b"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["c"]}})
    assert ["a", "b", "c"] == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})
  end

  test "can remove an element" do
    crdt = %DeltaCrdt.RemoveWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["b"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["c"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :remove, ["b"]}})
    assert ["a", "c"] == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})
  end

  test "can clear the set" do
    crdt = %DeltaCrdt.RemoveWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["b"]}})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :clear, []}})
    assert [] == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})
  end

  test "handles conflicts" do
    crdt = %DeltaCrdt.RemoveWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt3} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt1, {:add_neighbour, crdt3})
    send(crdt2, {:add_neighbour, crdt1})
    send(crdt2, {:add_neighbour, crdt3})
    send(crdt3, {:add_neighbour, crdt1})
    send(crdt3, {:add_neighbour, crdt2})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})
    GenServer.cast(crdt2, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["b"]}})
    GenServer.cast(crdt3, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["c"]}})
    send(crdt1, :ship_interval_or_state_to_all)
    send(crdt2, :ship_interval_or_state_to_all)
    send(crdt3, :ship_interval_or_state_to_all)
    Process.sleep(10)
    assert ~w(a b c) == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})
  end

  test "remove wins" do
    crdt = %DeltaCrdt.RemoveWinsSet{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt2, {:add_neighbour, crdt1})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})
    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.RemoveWinsSet, :add, ["a"]}})
    GenServer.cast(crdt2, {:operation, {DeltaCrdt.RemoveWinsSet, :remove, ["a"]}})
    send(crdt1, :ship_interval_or_state_to_all)
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)
    assert ~w() == GenServer.call(crdt1, {:read, DeltaCrdt.RemoveWinsSet})
  end
end
