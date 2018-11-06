defmodule DeltaCrdt.CausalDotSet do
  @moduledoc false

  defstruct causal_context: DeltaCrdt.CausalContext.new(),
            state: MapSet.new()

  def new(dots \\ [])
  def new([]), do: %__MODULE__{}
  def new(dots), do: %__MODULE__{state: MapSet.new(dots)}
end

defimpl DeltaCrdt.DotStore, for: DeltaCrdt.CausalDotSet do
  def dots(%{state: state}), do: state
end

defimpl DeltaCrdt.SemiLattice, for: DeltaCrdt.CausalDotSet do
  defp convert_bottom(%{state: :bottom} = set) do
    set |> Map.put(:state, MapSet.new())
  end

  defp convert_bottom(set), do: set

  def minimum_delta(state, delta), do: {join(state, delta), delta}

  def join(set1, set2) do
    set1 = convert_bottom(set1)
    set2 = convert_bottom(set2)

    state =
      MapSet.intersection(set1.state, set2.state)
      |> MapSet.union(
        MapSet.difference(set1.state, DeltaCrdt.CausalContext.dots(set2.causal_context))
      )
      |> MapSet.union(
        MapSet.difference(set2.state, DeltaCrdt.CausalContext.dots(set1.causal_context))
      )

    %DeltaCrdt.CausalDotSet{
      state: state,
      causal_context: DeltaCrdt.CausalContext.join(set1.causal_context, set2.causal_context)
    }
  end

  def bottom?(%{state: dots}) do
    Enum.empty?(dots)
  end

  def compress(s), do: s
end
