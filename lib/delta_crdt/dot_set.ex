defmodule DeltaCrdt.DotSet do
  defstruct dots: MapSet.new()

  def read(%{state: %DeltaCrdt.DotSet{dots: dots}}), do: MapSet.to_list(dots)
end
