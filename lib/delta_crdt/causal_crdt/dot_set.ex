defmodule DeltaCrdt.CausalCrdt.DotSet do
  @behaviour DeltaCrdt.CausalCrdt

  def new, do: {DeltaCrdt.CausalContext.new(), MapSet.new()}

  def join({s1, c1}, {s2, c2}) do
    new_s =
      MapSet.intersection(s1, s2)
      |> MapSet.union(MapSet.difference(s1, c2))
      |> MapSet.union(MapSet.difference(s2, c1))

    new_c = MapSet.union(c1, c2)

    {new_s, new_c}
  end

  def value(dots), do: MapSet.to_list(dots)
end
