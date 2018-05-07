defmodule DeltaCrdt.CausalCrdt.EnableWinsFlag do
  def enable({s, c}, i) do
    d = [DeltaCrdt.CausalContext.next(c, i)] |> Enum.into(MapSet.new())

    new_c = MapSet.union(d, s)

    {d, new_c}
  end

  def disable({s, c}, i) do
    {DeltaCrdt.CausalContext.new(), s}
  end

  def read({s, c}), do: !Enum.empty?(s)
end
