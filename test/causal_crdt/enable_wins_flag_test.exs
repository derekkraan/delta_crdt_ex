defmodule DeltaCrdt.CausalCrdt.EnableWinsFlagTest do
  use ExUnit.Case, async: true

  test "simultaneous enable and disable: enable wins" do
    original_state = DeltaCrdt.CausalCrdt.DotSet.new()

    mutation1 = DeltaCrdt.CausalCrdt.EnableWinsFlag.enable(original_state, 0)

    mutation2 = DeltaCrdt.CausalCrdt.EnableWinsFlag.disable(original_state, 1)

    assert true ==
             DeltaCrdt.CausalCrdt.DotSet.join(original_state, mutation1)
             |> DeltaCrdt.CausalCrdt.DotSet.join(mutation2)
             |> DeltaCrdt.CausalCrdt.EnableWinsFlag.read()
  end

  test "disabled later: disabled" do
    original_state = DeltaCrdt.CausalCrdt.DotSet.new()

    mutation1 = DeltaCrdt.CausalCrdt.EnableWinsFlag.enable(original_state, 0)

    state2 = DeltaCrdt.CausalCrdt.DotSet.join(original_state, mutation1)

    mutation2 = DeltaCrdt.CausalCrdt.EnableWinsFlag.disable(state2, 1)

    assert false ==
             DeltaCrdt.CausalCrdt.DotSet.join(state2, mutation2)
             |> DeltaCrdt.CausalCrdt.EnableWinsFlag.read()
  end

  test "with running CRDTs" do
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(DeltaCrdt.CausalCrdt.DotSet)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(DeltaCrdt.CausalCrdt.DotSet)
    {:ok, crdt3} = DeltaCrdt.CausalCrdt.start_link(DeltaCrdt.CausalCrdt.DotSet)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt1, {:add_neighbour, crdt3})
    send(crdt2, {:add_neighbour, crdt1})
    send(crdt2, {:add_neighbour, crdt3})
    send(crdt3, {:add_neighbour, crdt1})
    send(crdt3, {:add_neighbour, crdt2})
    GenServer.cast(crdt1, {:operation, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :enable, []}})

    assert true ==
             GenServer.call(crdt1, {:read, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :read, []}})

    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert true ==
             GenServer.call(crdt2, {:read, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :read, []}})

    assert true ==
             GenServer.call(crdt3, {:read, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :read, []}})

    GenServer.cast(crdt2, {:operation, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :disable, []}})
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert false ==
             GenServer.call(crdt1, {:read, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :read, []}})

    assert false ==
             GenServer.call(crdt2, {:read, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :read, []}})

    assert false ==
             GenServer.call(crdt3, {:read, {DeltaCrdt.CausalCrdt.EnableWinsFlag, :read, []}})
  end
end
