defmodule DeltaCrdt.ORMap do
  alias DeltaCrdt.{CausalDotMap, DummyCausalCrdt, CausalContext, DotStore}

  def apply({m, f, a} = op, key, i, %CausalDotMap{} = map) do
    val = Map.get(map.state, key, DummyCausalCrdt.new())
    delta_op = apply(m, f, a ++ [i, %{val | causal_context: map.causal_context}])

    %CausalDotMap{
      state: %{key => Map.put(delta_op, :causal_context, nil)},
      causal_context: delta_op.causal_context,
      keys: MapSet.new([key])
    }
  end

  def remove(key, i, %CausalDotMap{} = map) do
    val = Map.get(map.state, key, DummyCausalCrdt.new())

    %CausalDotMap{
      state: :bottom,
      causal_context: DotStore.dots(val) |> CausalContext.new(),
      keys: MapSet.new([key])
    }
  end

  def clear(i, %CausalDotMap{} = map) do
    %CausalDotMap{
      state: :bottom,
      causal_context: DotStore.dots(map) |> CausalContext.new(),
      keys: map.keys
    }
  end
end
