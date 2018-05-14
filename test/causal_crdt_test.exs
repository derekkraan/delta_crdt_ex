defmodule DeltaCrdt.CausalCrdtTest do
  use ExUnit.Case, async: true

  test "notifies pid when state is updated" do
    crdt = %DeltaCrdt.EnableWinsFlag{}
    {:ok, crdt1} = DeltaCrdt.CausalCrdt.start_link(crdt, {self(), :updated_state})
    {:ok, crdt2} = DeltaCrdt.CausalCrdt.start_link(crdt)
    send(crdt1, {:add_neighbour, crdt2})
    send(crdt2, {:add_neighbour, crdt1})

    GenServer.cast(crdt1, {:operation, {DeltaCrdt.EnableWinsFlag, :enable, []}})
    assert_receive :updated_state

    GenServer.cast(crdt2, {:operation, {DeltaCrdt.EnableWinsFlag, :disable, []}})
    send(crdt2, :ship_interval_or_state_to_all)
    assert_receive :updated_state
  end
end
