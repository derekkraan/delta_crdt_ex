defmodule DeltaCrdt.EnableWinsFlag do
  defstruct state: %DeltaCrdt.Causal{state: %DeltaCrdt.DotSet{}}

  def enable(%{state: %{state: s, context: c}}, i) do
    d = [DeltaCrdt.Causal.next(c, i)] |> MapSet.new()

    new_c = MapSet.union(d, s.dots)

    %__MODULE__{state: %DeltaCrdt.Causal{context: new_c, state: %DeltaCrdt.DotSet{dots: d}}}
  end

  def disable(%{state: %{state: s, context: c}}, _i) do
    %__MODULE__{
      state: %DeltaCrdt.Causal{
        state: %DeltaCrdt.DotSet{},
        context: s.dots
      }
    }
  end

  def read(%{state: d}), do: !Enum.empty?(DeltaCrdt.DotStore.dots(d.state))
end
