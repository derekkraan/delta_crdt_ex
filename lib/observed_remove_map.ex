defmodule DeltaCrdt.ObservedRemoveMap do
  defstruct state: %DeltaCrdt.Causal{state: %DeltaCrdt.DotMap{}}

  def apply(%{state: %{state: s, context: c}}, i, {module, delta_mutator, value}, k) do
    state = Map.get(s.map, k, :bottom)
    sub_crdt = %DeltaCrdt.Causal{context: c, state: state}

    %{state: %{state: v, context: new_c}} = apply(module, delta_mutator, [sub_crdt, i, value])

    %__MODULE__{
      state: %DeltaCrdt.Causal{
        state: %DeltaCrdt.DotMap{
          map: %{k => v}
        },
        context: new_c
      }
    }
  end

  def remove(%{state: %{state: s, context: c}}, _i, e) do
    %__MODULE__{
      state: %DeltaCrdt.Causal{
        state: %DeltaCrdt.DotMap{},
        context:
          DeltaCrdt.DotStore.dots(Map.get(s.map, e, %DeltaCrdt.DotSet{}))
          |> Enum.into(MapSet.new())
      }
    }
  end

  def clear(%{state: %{state: s, context: c}}, _i) do
    %__MODULE__{
      state: %DeltaCrdt.Causal{
        state: %DeltaCrdt.DotMap{},
        context: DeltaCrdt.DotStore.dots(s) |> Enum.into(MapSet.new())
      }
    }
  end
end
