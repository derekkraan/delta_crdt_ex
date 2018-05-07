defmodule DeltaCrdt.DotMap do
  defstruct map: %{}

  def read(%{state: %DeltaCrdt.DotMap{map: map}}),
    do: Enum.map(fn {_k, dots} -> read(dots) end) |> Enum.reduce(&Kernel.++/2) |> Enum.uniq()
end
