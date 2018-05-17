defmodule DeltaCrdt.EnableWinsFlagTest do
  use ExUnit.Case, async: true

  test "simultaneous enable and disable: enable wins" do
    crdt = %DeltaCrdt.EnableWinsFlag{}
    mutation1 = DeltaCrdt.EnableWinsFlag.enable(crdt, 0)
    mutation2 = DeltaCrdt.EnableWinsFlag.disable(crdt, 1)

    assert true ==
             DeltaCrdt.JoinSemilattice.join(crdt, mutation1)
             |> DeltaCrdt.JoinSemilattice.join(mutation2)
             |> DeltaCrdt.EnableWinsFlag.read()
  end

  test "disabled later: disabled" do
    crdt = %DeltaCrdt.EnableWinsFlag{}

    mutation1 = DeltaCrdt.EnableWinsFlag.enable(crdt, 0)

    state2 = DeltaCrdt.JoinSemilattice.join(crdt, mutation1)

    mutation2 = DeltaCrdt.EnableWinsFlag.disable(state2, 1)

    assert false ==
             DeltaCrdt.JoinSemilattice.join(state2, mutation2)
             |> DeltaCrdt.EnableWinsFlag.read()
  end

  test "with running CRDTs" do
    crdt = %DeltaCrdt.EnableWinsFlag{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    {:ok, crdt3} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt1, {:add_neighbour, crdt3})
    send(crdt2, {:add_neighbour, crdt1})
    send(crdt2, {:add_neighbour, crdt3})
    send(crdt3, {:add_neighbour, crdt1})
    send(crdt3, {:add_neighbour, crdt2})
    GenServer.call(crdt1, {:operation, {DeltaCrdt.EnableWinsFlag, :enable, []}})

    assert true == GenServer.call(crdt1, {:read, DeltaCrdt.EnableWinsFlag})

    send(crdt1, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert true == GenServer.call(crdt2, {:read, DeltaCrdt.EnableWinsFlag})
    assert true == GenServer.call(crdt3, {:read, DeltaCrdt.EnableWinsFlag})

    GenServer.cast(crdt2, {:operation, {DeltaCrdt.EnableWinsFlag, :disable, []}})
    send(crdt2, :ship_interval_or_state_to_all)
    Process.sleep(10)

    assert false == GenServer.call(crdt1, {:read, DeltaCrdt.EnableWinsFlag})
    assert false == GenServer.call(crdt2, {:read, DeltaCrdt.EnableWinsFlag})
    assert false == GenServer.call(crdt3, {:read, DeltaCrdt.EnableWinsFlag})
  end
end
