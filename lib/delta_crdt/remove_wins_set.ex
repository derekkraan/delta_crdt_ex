defmodule DeltaCrdt.RemoveWinsSet do
  defstruct state: %DeltaCrdt.Causal{state: %DeltaCrdt.DotMap{}}

  def add(%{state: %{state: s, context: c}}, i, e) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())

    new_c =
      Map.get(s.map, e, %DeltaCrdt.DotMap{}).map |> Enum.into(MapSet.new()) |> MapSet.union(d)

    %__MODULE__{
      state: %DeltaCrdt.Causal{
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

  def remove(%{state: %{state: s, context: c}}, i, e) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())

    new_c =
      Map.get(s.map, e, %DeltaCrdt.DotMap{}).map |> Enum.into(MapSet.new()) |> MapSet.union(d)

    %__MODULE__{
      state: %DeltaCrdt.Causal{
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

  def clear(%{state: %{state: s, context: c}}, i) do
    %__MODULE__{
      state: %DeltaCrdt.Causal{
        context: DeltaCrdt.DotStore.dots(s) |> Enum.into(MapSet.new()),
        state: %DeltaCrdt.DotMap{}
      }
    }
  end

  def read(%{state: %{state: %{map: map}, context: c}}) do
    Enum.reject(map, fn {_key, val} ->
      val.map |> Map.keys() |> Enum.member?(false)
    end)
    |> Enum.map(fn {key, _} -> key end)
  end
end
