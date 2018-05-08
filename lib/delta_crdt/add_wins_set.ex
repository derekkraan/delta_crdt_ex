defmodule DeltaCrdt.AddWinsSet do
  defstruct crdt: %DeltaCrdt.Causal{state: %DeltaCrdt.DotMap{}}

  def add(%{crdt: %{state: s, context: c}}, i, e) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())
    new_c = Map.get(s.map, e, %DeltaCrdt.DotSet{}).dots |> MapSet.union(d)

    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        context: new_c,
        state: %DeltaCrdt.DotMap{
          map: %{
            e => %DeltaCrdt.DotSet{
              dots: d
            }
          }
        }
      }
    }
  end

  def remove(%{crdt: %{state: s, context: c}}, i, e) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())

    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        context: Map.get(s.map, e, %DeltaCrdt.DotSet{}).dots,
        state: %DeltaCrdt.DotMap{}
      }
    }
  end

  def clear(%{crdt: %{state: s, context: c}}, _i) do
    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        context: DeltaCrdt.DotStore.dots(s) |> Enum.into(MapSet.new()),
        state: %DeltaCrdt.DotMap{}
      }
    }
  end

  def read(%{crdt: %{state: %{map: map}, context: c}} = thing) do
    Map.keys(map)
  end
end
