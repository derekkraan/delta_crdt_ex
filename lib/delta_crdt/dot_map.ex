defmodule DeltaCrdt.DotMap do
  defstruct map: %{}
end

defimpl DeltaCrdt.DotStore, for: DeltaCrdt.DotMap do
  def dots(%DeltaCrdt.DotMap{map: map}) do
    Enum.map(map, fn {_k, dots} -> DeltaCrdt.DotStore.dots(dots) end)
    |> List.flatten()
    |> Enum.uniq()
  end
end

defimpl DeltaCrdt.JoinSemilattice, for: DeltaCrdt.DotMap do
  def bottom?(%{map: map}) when map_size(map) == 0, do: true
  def bottom?(_), do: false
end
