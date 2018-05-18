defmodule DeltaCrdt.Causal do
  defstruct state: nil, context: MapSet.new()

  def maximum(c, i) when is_list(c) do
    Enum.map(c, fn
      {^i, val} -> val
      _ -> 0
    end)
    |> Enum.max(fn -> -1 end)
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
  def bottom?(%{state: state}), do: DeltaCrdt.JoinSemilattice.bottom?(state)

  def compress(%{context: c} = state) do
    new_c =
      Enum.reduce(c, %{}, fn {i, x}, acc ->
        Map.update(acc, i, x, fn
          y when y > x -> y
          _y -> x
        end)
      end)
      |> MapSet.new()

    %{state | context: new_c}
  end

  def join(%{state: :bottom} = crdt1, %{state: %DeltaCrdt.DotSet{}} = crdt2),
    do: join(%{crdt1 | state: %DeltaCrdt.DotSet{}}, crdt2)

  def join(%{state: %DeltaCrdt.DotSet{}} = crdt1, %{state: :bottom} = crdt2),
    do: join(crdt1, %{crdt2 | state: %DeltaCrdt.DotSet{}})

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

  def join(%{state: :bottom} = crdt1, %{state: %DeltaCrdt.DotFunction{}} = crdt2),
    do: join(%{crdt1 | state: %DeltaCrdt.DotFunction{}}, crdt2)

  def join(%{state: %DeltaCrdt.DotFunction{}} = crdt1, %{state: :bottom} = crdt2),
    do: join(crdt1, %{crdt2 | state: %DeltaCrdt.DotFunction{}})

  def join(%{context: c1, state: %DeltaCrdt.DotFunction{map: map1}}, %{
        context: c2,
        state: %DeltaCrdt.DotFunction{map: map2}
      }) do
    keys1 = Map.keys(map1) |> MapSet.new()
    keys2 = Map.keys(map2) |> MapSet.new()

    term1 =
      MapSet.intersection(keys1, keys2)
      |> Enum.map(fn key ->
        {key, DeltaCrdt.JoinSemilattice.join(Map.get(map1, key), Map.get(map2, key))}
      end)
      |> Map.new()

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

  def join(%{state: :bottom} = crdt1, %{state: %DeltaCrdt.DotMap{}} = crdt2),
    do: join(%{crdt1 | state: %DeltaCrdt.DotMap{}}, crdt2)

  def join(%{state: %DeltaCrdt.DotMap{}} = crdt1, %{state: :bottom} = crdt2),
    do: join(crdt1, %{crdt2 | state: %DeltaCrdt.DotMap{}})

  def join(%{context: c1, state: %DeltaCrdt.DotMap{map: map1}}, %{
        context: c2,
        state: %DeltaCrdt.DotMap{map: map2}
      }) do
    all_keys = (Map.keys(map1) ++ Map.keys(map2)) |> Enum.uniq()

    new_map =
      Enum.map(all_keys, fn key ->
        val =
          DeltaCrdt.JoinSemilattice.join(
            %DeltaCrdt.Causal{context: c1, state: Map.get(map1, key, :bottom)},
            %DeltaCrdt.Causal{context: c2, state: Map.get(map2, key, :bottom)}
          )
          |> Map.get(:state)

        {key, val}
      end)
      |> Enum.reject(fn {_key, state} -> DeltaCrdt.JoinSemilattice.bottom?(state) end)
      |> Map.new()

    new_c = MapSet.union(c1, c2)

    %DeltaCrdt.Causal{context: new_c, state: %DeltaCrdt.DotMap{map: new_map}}
  end
end
