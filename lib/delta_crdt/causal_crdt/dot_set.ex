defmodule DeltaCrdt.CausalCrdt.DotSet do
  @behaviour DeltaCrdt.CausalCrdt

  @type dot :: {node :: any, sequence :: integer(), value :: any}

  def new, do: {DeltaCrdt.CausalContext.new(), []}

  def join({s1, c1}, {s2, c2}) do
    [ss1, sc1, ss2, sc2] = [s1, c1, s2, c2] |> Enum.map(fn x -> Enum.into(x, MapSet.new()) end)

    new_s =
      MapSet.intersection(ss1, ss2)
      |> MapSet.union(MapSet.difference(ss1, sc2))
      |> MapSet.union(MapSet.difference(ss2, sc1))
      |> Enum.into([])

    new_c = MapSet.union(sc1, sc2)
    # new_c = DeltaCrdt.CausalContext.union(c1, c2)

    {new_s, new_c}
  end

  def value(dots), do: dots
end
