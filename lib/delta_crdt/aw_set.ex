defmodule DeltaCrdt.AWSet do
  @moduledoc """
  An add-wins set.

  This CRDT represents a set with add-wins semantics. So in the event of a conflict between an add and a remove operation, the add operation will win and the element will remain in the set.
  """

  def new(), do: %DeltaCrdt.CausalDotMap{}

  def add(element, i, %{causal_context: c, state: map} = a) do
    {next_dot, _new_c} = DeltaCrdt.CausalContext.next(c, i)

    causal_context =
      Map.get(map, element, DeltaCrdt.CausalContext.new()).dots
      |> MapSet.put(next_dot)
      |> DeltaCrdt.CausalContext.new()

    %DeltaCrdt.CausalDotMap{
      state: %{element => DeltaCrdt.CausalDotSet.new([next_dot])},
      keys: MapSet.new([element]),
      causal_context: causal_context
    }
  end

  def remove(element, _i, %{causal_context: _c, state: map}) do
    causal_context =
      Map.get(map, element, DeltaCrdt.CausalContext.new()) |> DeltaCrdt.CausalContext.new()

    %DeltaCrdt.CausalDotMap{
      state: %{},
      keys: MapSet.new([element]),
      causal_context: causal_context
    }
  end

  def clear(_i, map) do
    causal_context = DeltaCrdt.DotStore.dots(map) |> DeltaCrdt.CausalContext.new()

    %DeltaCrdt.CausalDotMap{
      state: %{},
      keys: MapSet.new(Map.keys(map.state)),
      causal_context: causal_context
    }
  end
end
