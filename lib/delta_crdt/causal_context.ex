defmodule DeltaCrdt.CausalContext do
  def union(c_a, c_b) do
    (Map.keys(c_a) ++ Map.keys(c_b))
    |> Enum.uniq()
    |> Enum.map(fn key -> {key, Enum.max([Map.get(c_a, key, 0), Map.get(c_b, key, 0)])} end)
    |> Enum.into(%{})
  end

  @new []

  def new, do: @new

  def maximum(%{} = c, i), do: Map.get(c, i, 0)

  def maximum(c, i) when is_list(c) do
    Enum.map(c, fn
      {^i, val} -> val
      _ -> 0
    end)
    |> Enum.max(fn -> 0 end)
  end

  def next(c, i) do
    {i, maximum(c, i) + 1}
  end
end
