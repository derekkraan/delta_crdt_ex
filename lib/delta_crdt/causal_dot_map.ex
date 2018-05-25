defmodule DeltaCrdt.CausalDotMap do
  defstruct causal_context: DeltaCrdt.CausalContext.new(),
            keys: MapSet.new(),
            state: %{}

  def new(), do: %__MODULE__{}
end

defimpl DeltaCrdt.DotStore, for: DeltaCrdt.CausalDotMap do
  def dots(map) do
    Enum.flat_map(map.state, fn {_k, dot_store} ->
      DeltaCrdt.DotStore.dots(dot_store)
    end)
  end
end

defimpl DeltaCrdt.SemiLattice, for: DeltaCrdt.CausalDotMap do
  defp convert_bottom(%{state: :bottom} = map) do
    Map.put(map, :state, %{})
    |> Map.put_new(:keys, MapSet.new())
  end

  defp convert_bottom(map), do: map

  def join(map1, map2) do
    map1 = convert_bottom(map1)
    map2 = convert_bottom(map2)

    intersecting_keys =
      if Enum.empty?(map1.keys) || Enum.empty?(map2.keys) do
        [map1, map2]
        |> Enum.map(fn map -> Map.keys(map.state) |> MapSet.new() end)
        |> Enum.reduce(&MapSet.union/2)
      else
        MapSet.intersection(map1.keys, map2.keys)
      end

    all_keys = MapSet.union(map1.keys, map2.keys)

    resolved_conflicts =
      Enum.map(intersecting_keys, fn key ->
        sub1 = Map.get(map1.state, key, %{state: :bottom})
        sub2 = Map.get(map2.state, key, %{state: :bottom})

        new_sub =
          DeltaCrdt.SemiLattice.join(
            Map.put(sub1, :causal_context, map1.causal_context),
            Map.put(sub2, :causal_context, map2.causal_context)
          )

        {key, Map.put(new_sub, :causal_context, nil)}
      end)
      |> Enum.reject(fn {_key, val} -> DeltaCrdt.SemiLattice.bottom?(val) end)
      |> Map.new()

    new_state =
      Map.drop(map1.state, intersecting_keys)
      |> Map.merge(Map.drop(map2.state, intersecting_keys))
      |> Map.merge(resolved_conflicts)

    new_causal_context = DeltaCrdt.CausalContext.join(map1.causal_context, map2.causal_context)

    %DeltaCrdt.CausalDotMap{causal_context: new_causal_context, state: new_state, keys: all_keys}
  end

  def compress(map) do
    %{
      map
      | causal_context: DeltaCrdt.CausalContext.compress(map.causal_context),
        keys: MapSet.new(Map.keys(map.state))
    }
  end

  def bottom?(map) do
    Enum.empty?(map.state)
  end
end
