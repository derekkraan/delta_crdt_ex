defmodule DeltaCrdt.Causal do
  defstruct state: nil, context: MapSet.new()

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

defimpl DeltaCrdt.JoinSemilattice, for: DeltaCrdt.Causal do
  def join(%{context: c1, state: %DeltaCrdt.DotSet{dots: dots1}}, %{
        context: c2,
        state: %DeltaCrdt.DotSet{dots: dots2}
      }) do
    new_dots =
      MapSet.intersection(dots1, dots2)
      |> MapSet.union(MapSet.difference(dots1, c2))
      |> MapSet.union(MapSet.difference(dots2, c1))

    new_c = MapSet.union(c1, c2)

    %DeltaCrdt.Causal{context: new_c, state: %DeltaCrdt.DotSet{dots: new_dots}}
  end

  def read(%{state: %DeltaCrdt.DotSet{dots: dots}}), do: MapSet.to_list(dots)

  def join(%{context: c1, state: %DeltaCrdt.DotFunction{map: map1}}, %{
        context: c2,
        state: %DeltaCrdt.DotFunction{map: map2}
      }) do
    keys1 = Map.keys(map1) |> Enum.into(MapSet.new())
    keys2 = Map.keys(map2) |> Enum.into(MapSet.new())

    term1 =
      MapSet.intersection(keys1, keys2)
      |> Enum.map(fn key ->
        {key, DeltaCrdt.JoinSemilattice.join(Map.get(map1, key), Map.get(map2, key))}
      end)
      |> Enum.into(%{})

    term2 =
      Enum.reject(map1, fn {d, v} ->
        MapSet.member?(c2, d)
      end)

    term3 =
      Enum.reject(map2, fn {d, v} ->
        MapSet.member?(c1, d)
      end)

    new_map = term1 |> Map.merge(term2) |> Map.merge(term3)

    new_c = MapSet.union(c1, c2)

    %DeltaCrdt.Causal{context: new_c, state: %DeltaCrdt.DotFunction{map: new_map}}
  end

  def read(%{state: %DeltaCrdt.DotFunction{map: map}}), do: Map.keys(map)

  def join(%{context: c1, state: %DeltaCrdt.DotMap{map: map1}}, %{
        context: c2,
        state: %DeltaCrdt.DotMap{map: map2}
      }) do
    keys1 = Map.keys(map1) |> Enum.into(MapSet.new())
    keys2 = Map.keys(map2) |> Enum.into(MapSet.new())

    new_map =
      MapSet.intersection(keys1, keys2)
      |> Enum.map(fn key ->
        {key,
         DeltaCrdt.JoinSemilattice.join(
           %DeltaCrdt.Causal{context: c1, state: Map.get(map1, key)},
           %DeltaCrdt.Causal{context: c2, state: Map.get(map2, key)}
         )
         |> elem(0)}
      end)
      |> Enum.reject(fn
        {_key, :bottom} -> true
        _ -> false
      end)
      |> Enum.into(%{})

    new_c = MapSet.union(c1, c2)

    %DeltaCrdt.Causal{context: new_c, state: %DeltaCrdt.DotFunction{map: new_map}}
  end

  def read(%{state: %DeltaCrdt.DotMap{map: map}}),
    do: Enum.map(fn {_k, dots} -> read(dots) end) |> Enum.reduce(&Kernel.++/2) |> Enum.uniq()
end
