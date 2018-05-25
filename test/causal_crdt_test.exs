defmodule CausalCrdtTest do
  use ExUnit.Case, async: true

  alias DeltaCrdt.{CausalCrdt, AWLWWMap}

  setup do
    {:ok, c1} = CausalCrdt.start_link(AWLWWMap.new())
    {:ok, c2} = CausalCrdt.start_link(AWLWWMap.new())
    {:ok, c3} = CausalCrdt.start_link(AWLWWMap.new())
    send(c1, {:add_neighbours, [c2, c3]})
    send(c2, {:add_neighbours, [c1, c3]})
    send(c3, {:add_neighbours, [c2, c1]})
    [c1: c1, c2: c2, c3: c3]
  end

  test "works", context do
    GenServer.cast(context.c1, {:operation, {AWLWWMap, :add, ["Derek", "Kraan"]}})
    GenServer.cast(context.c1, {:operation, {AWLWWMap, :add, [:Tonci, "Galic"]}})

    assert %{"Derek" => "Kraan", Tonci: "Galic"} == GenServer.call(context.c1, {:read, AWLWWMap})
  end

  test "conflicting updates resolve", context do
    GenServer.cast(context.c1, {:operation, {AWLWWMap, :add, ["Derek", "one_wins"]}})
    GenServer.cast(context.c2, {:operation, {AWLWWMap, :add, ["Derek", "two_wins"]}})
    GenServer.cast(context.c3, {:operation, {AWLWWMap, :add, ["Derek", "three_wins"]}})
    send(context.c1, :ship_interval_or_state_to_all)
    send(context.c2, :ship_interval_or_state_to_all)
    send(context.c3, :ship_interval_or_state_to_all)
    Process.sleep(50)
    assert %{"Derek" => "three_wins"} == GenServer.call(context.c1, {:read, AWLWWMap})
  end

  test "add wins", context do
    GenServer.cast(context.c1, {:operation, {AWLWWMap, :add, ["Derek", "add_wins"]}})
    GenServer.cast(context.c2, {:operation, {AWLWWMap, :remove, ["Derek"]}})
    send(context.c1, :ship_interval_or_state_to_all)
    send(context.c2, :ship_interval_or_state_to_all)
    Process.sleep(20)
    assert %{"Derek" => "add_wins"} == GenServer.call(context.c1, {:read, AWLWWMap})
  end

  test "can remove", context do
    GenServer.cast(context.c1, {:operation, {AWLWWMap, :add, ["Derek", "add_wins"]}})
    send(context.c1, :ship_interval_or_state_to_all)
    Process.sleep(20)
    GenServer.cast(context.c2, {:operation, {AWLWWMap, :remove, ["Derek"]}})
    send(context.c2, :ship_interval_or_state_to_all)
    Process.sleep(20)
    assert %{} == GenServer.call(context.c1, {:read, AWLWWMap})
  end
end
