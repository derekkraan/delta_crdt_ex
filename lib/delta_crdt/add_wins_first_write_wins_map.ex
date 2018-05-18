defmodule DeltaCrdt.AddWinsFirstWriteWinsMap do
  @moduledoc """
  AddWinsFirstWriteWinsMap<K -> V> = ObservedRemoveMap<K -> AWSet<V>>
  """

  defstruct state: %DeltaCrdt.ObservedRemoveMap{}

  def add(crdt, i, key, val) do
    DeltaCrdt.ObservedRemoveMap.remove(crdt, i, key)
    |> DeltaCrdt.JoinSemilattice.join(
      DeltaCrdt.ObservedRemoveMap.apply(
        crdt,
        i,
        {DeltaCrdt.AddWinsSet, :add, {System.system_time(:nanosecond), val}},
        key
      )
    )
  end

  def remove(crdt, i, key) do
    DeltaCrdt.ObservedRemoveMap.remove(crdt, i, key)
  end

  def read(%{state: %{state: %{map: map}}}) do
    map
    |> Map.new(fn {key, %{map: vals}} ->
      {_, val} = Map.keys(vals) |> Enum.min_by(fn {timestamp, _} -> timestamp end)

      {key, val}
    end)
  end
end
