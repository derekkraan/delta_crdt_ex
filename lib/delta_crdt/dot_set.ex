defmodule DeltaCrdt.DotSet do
  defstruct dots: MapSet.new()
end

defimpl DeltaCrdt.DotStore, for: DeltaCrdt.DotSet do
  def dots(%{dots: dots}), do: MapSet.to_list(dots)
end

defimpl DeltaCrdt.JoinSemilattice, for: DeltaCrdt.DotSet do
  def bottom?(%{dots: dots}), do: MapSet.size(dots) == 0
end
