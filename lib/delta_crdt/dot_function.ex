defmodule DeltaCrdt.DotFunction do
  defstruct map: %{}
  def read(%{state: %DeltaCrdt.DotFunction{map: map}}), do: Map.keys(map)
end
