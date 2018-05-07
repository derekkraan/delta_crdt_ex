defmodule DeltaCrdt.CausalContext do
  @type t :: MapSet.t()

  def new, do: MapSet.new()

  def maximum(c, i) when is_list(c) do
    Enum.map(c, fn
      {^i, val} -> val
      _ -> 0
    end)
    |> Enum.max(fn -> 0 end)
  end

  def maximum(c, i) do
    c
    |> MapSet.to_list()
    |> maximum(i)
  end

  def next(c, i) do
    {i, maximum(c, i) + 1}
  end
end
