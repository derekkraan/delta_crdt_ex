defmodule DeltaCrdt.DotFunction do
  defstruct map: %{}
end

defimpl DeltaCrdt.DotStore, for: DeltaCrdt.DotFunction do
  def dots(%{map: map}), do: Map.keys(map)
end

defimpl DeltaCrdt.JoinSemilattice, for: DeltaCrdt.DotFunction do
  def bottom?(%{map: map}) when map_size(map) == 0, do: true
  def bottom?(_), do: false
end
