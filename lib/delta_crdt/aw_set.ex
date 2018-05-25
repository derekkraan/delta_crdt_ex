defmodule DeltaCrdt.AWSet do
  def new(), do: %DeltaCrdt.CausalDotMap{}

  def add(element, i, %{causal_context: c}) do
    {next_dot, new_c} = DeltaCrdt.CausalContext.next(c, i)

    %DeltaCrdt.CausalDotMap{
      state: %{element => DeltaCrdt.CausalDotSet.new([next_dot])},
      keys: MapSet.new([element]),
      causal_context: new_c
    }
  end

  def remove(element, i, %{causal_context: c, state: map}) do
    causal_context =
      Map.get(map, element, DeltaCrdt.CausalContext.new()) |> DeltaCrdt.CausalContext.new()

    %DeltaCrdt.CausalDotMap{
      state: %{},
      keys: MapSet.new([element]),
      causal_context: causal_context
    }
  end

  def clear(i, map) do
    causal_context = DeltaCrdt.DotStore.dots(map) |> DeltaCrdt.CausalContext.new()

    %DeltaCrdt.CausalDotMap{
      state: %{},
      keys: MapSet.new(Map.keys(map.state)),
      causal_context: causal_context
    }
  end
end
