defmodule DeltaCrdt.EnableWinsFlag do
  defstruct crdt: %DeltaCrdt.Causal{state: %DeltaCrdt.DotSet{}}

  def enable(%{crdt: %{state: s, context: c}}, i) do
    d = [DeltaCrdt.Causal.next(c, i)] |> Enum.into(MapSet.new())

    new_c = MapSet.union(d, s.dots)

    %__MODULE__{crdt: %DeltaCrdt.Causal{context: new_c, state: %DeltaCrdt.DotSet{dots: d}}}
  end

  def disable(%{crdt: %{state: s, context: c}}, _i) do
    %__MODULE__{
      crdt: %DeltaCrdt.Causal{
        state: %DeltaCrdt.DotSet{},
        context: s.dots
      }
    }
  end
end

defimpl DeltaCrdt.JoinSemilattice, for: DeltaCrdt.EnableWinsFlag do
  def join(s1, s2) do
    %DeltaCrdt.EnableWinsFlag{
      crdt: DeltaCrdt.JoinSemilattice.join(s1.crdt, s2.crdt)
    }
  end

  def read(%{crdt: d}), do: !Enum.empty?(DeltaCrdt.JoinSemilattice.read(d))
end
