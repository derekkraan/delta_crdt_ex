defmodule DeltaCrdt.CausalCrdt.EnableWinsFlag do
  def enable({s, c}, i) do
    d = [DeltaCrdt.CausalContext.next(c, i)]

    d_set = Enum.into(d, MapSet.new())
    s_set = Enum.into(s, MapSet.new())

    new_c =
      MapSet.union(d_set, s_set)
      |> Enum.into([])

    {d, new_c}
  end

  def disable({s, c}, i) do
    {[], s}
  end

  def read({s, c}), do: !Enum.empty?(s)
end
