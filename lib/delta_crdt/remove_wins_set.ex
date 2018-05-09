defmodule DeltaCrdt.RemoveWinsSet do
  defstruct crdt: %DeltaCrdt.Causal{state: %DeltaCrdt.DotMap{}}

  def add(%{crdt: %{state: s, context: c}}, i, e) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())

    new_c =
      Map.get(s.map, e, %DeltaCrdt.DotMap{}).map |> Enum.into(MapSet.new()) |> MapSet.union(d)

    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        context: new_c,
        state: %DeltaCrdt.DotMap{
          map: %{
            e => %DeltaCrdt.DotMap{
              map: %{true => %DeltaCrdt.DotSet{dots: d}}
            }
          }
        }
      }
    }
  end

  def remove(%{crdt: %{state: s, context: c}}, i, e) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())

    new_c =
      Map.get(s.map, e, %DeltaCrdt.DotMap{}).map |> Enum.into(MapSet.new()) |> MapSet.union(d)

    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        context: new_c,
        state: %DeltaCrdt.DotMap{
          map: %{
            e => %DeltaCrdt.DotMap{
              map: %{false => %DeltaCrdt.DotSet{dots: d}}
            }
          }
        }
      }
    }
  end

  def clear(%{crdt: %{state: s, context: c}}, i) do
    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        context: DeltaCrdt.DotStore.dots(s) |> Enum.into(MapSet.new()),
        state: %DeltaCrdt.DotMap{}
      }
    }
  end

  def read(%{crdt: %{state: %{map: map}, context: c}}) do
    Enum.reject(map, fn {_key, val} ->
      val.map |> Map.keys() |> Enum.member?(false)
    end)
    |> Enum.map(fn {key, _} -> key end)
  end
end
