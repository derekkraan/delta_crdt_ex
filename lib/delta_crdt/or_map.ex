defmodule DeltaCrdt.ORMap do
  alias DeltaCrdt.{CausalDotMap, DummyCausalCrdt, CausalContext, DotStore}

  def apply({m, f, a}, key, i, %CausalDotMap{} = map) do
    val = Map.get(map.state, key, DummyCausalCrdt.new())
    delta_op = apply(m, f, a ++ [i, %{val | causal_context: map.causal_context}])

    new_state =
      Map.new(delta_op.state, fn {key, thing} -> {key, Map.put(thing, :causal_context, nil)} end)

    new_delta_op =
      delta_op
      |> Map.put(:state, new_state)
      |> Map.put(:causal_context, nil)

    %CausalDotMap{
      state: %{key => new_delta_op},
      causal_context: delta_op.causal_context,
      keys: MapSet.new([key])
    }
  end

  def remove(key, _i, %CausalDotMap{} = map) do
    val = Map.get(map.state, key, DummyCausalCrdt.new())

    %CausalDotMap{
      state: :bottom,
      causal_context: DotStore.dots(val) |> CausalContext.new(),
      keys: MapSet.new([key])
    }
  end

  def clear(_i, %CausalDotMap{} = map) do
    %CausalDotMap{
      state: :bottom,
      causal_context: DotStore.dots(map) |> CausalContext.new(),
      keys: map.keys
    }
  end
end
