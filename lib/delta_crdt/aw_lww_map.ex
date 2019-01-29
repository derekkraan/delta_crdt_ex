defmodule DeltaCrdt.AWLWWMap do
  defstruct keys: MapSet.new(),
            dots: MapSet.new(),
            value: %{}

  def new(), do: %__MODULE__{}

  def add(key, value, i, state) do
    fn aw_set, context ->
      aw_set_add(i, {value, System.system_time(:nanosecond)}, {aw_set, context})
    end
    |> apply_op(key, state)
  end

  def remove(key, _i, state) do
    %{value: val} = state

    to_remove_dots =
      case Map.fetch(val, key) do
        {:ok, value} -> Enum.flat_map(value, fn {_val, to_remove_dots} -> to_remove_dots end)
        :error -> []
      end

    %__MODULE__{
      dots: MapSet.new(to_remove_dots),
      keys: MapSet.new([key]),
      value: %{}
    }
  end

  def clear(_i, state) do
    Map.put(state, :value, %{})
  end

  def minimum_deltas(delta, state) do
    join_decomposition(delta)
    |> Enum.filter(fn delta -> expansion?(delta, state) end)
  end

  def expansion?(%{value: val} = d, state) when map_size(val) == 0 do
    # check remove expansion
    case Enum.to_list(d.dots) do
      [] -> false
      [dot] -> MapSet.member?(state.dots, dot)
    end
  end

  def expansion?(d, state) do
    # check add expansion
    case Enum.to_list(d.dots) do
      [] ->
        false

      [dot] ->
        !MapSet.member?(state.dots, dot)
    end
  end

  def join_decomposition(%{value: val} = delta) do
    dots_to_deltas =
      Enum.flat_map(val, fn {key, dot_map} ->
        Enum.flat_map(dot_map, fn {_key, dots} ->
          Enum.map(dots, fn dot -> {dot, key} end)
        end)
      end)
      |> Map.new()

    Enum.map(delta.dots, fn dot ->
      case Map.get(dots_to_deltas, dot) do
        nil ->
          %__MODULE__{
            dots: MapSet.new([dot]),
            keys: delta.keys,
            value: %{}
          }

        key ->
          dots = Map.get(val, key)

          %__MODULE__{
            dots: MapSet.new([dot]),
            keys: MapSet.new([key]),
            value: %{key => dots}
          }
      end
    end)
  end

  def join(delta1, delta2, nested_joins \\ [:join, :dot_set_join]) do
    val1 = delta1.value
    val2 = delta2.value

    intersecting_keys =
      if(Enum.empty?(delta1.keys) || Enum.empty?(delta2.keys)) do
        # "no keys" means that we have to check every key
        MapSet.new(Map.keys(val1) ++ Map.keys(val2))
      else
        MapSet.intersection(delta1.keys, delta2.keys)
      end

    new_keys = MapSet.union(delta1.keys, delta2.keys)
    new_dots = MapSet.union(delta1.dots, delta2.dots)

    resolved_conflicts =
      Enum.flat_map(intersecting_keys, fn key ->
        sub_delta1 =
          Map.put(delta1, :value, Map.get(delta1.value, key, %{}))
          |> Map.put(:keys, MapSet.new())

        sub_delta2 =
          Map.put(delta2, :value, Map.get(delta2.value, key, %{}))
          |> Map.put(:keys, MapSet.new())

        [next_join | other_joins] = nested_joins

        %{value: new_sub} = apply(__MODULE__, next_join, [sub_delta1, sub_delta2, other_joins])

        if Enum.empty?(new_sub) do
          []
        else
          [{key, new_sub}]
        end
      end)
      |> Map.new()

    new_val =
      Map.drop(delta1.value, intersecting_keys)
      |> Map.merge(Map.drop(delta2.value, intersecting_keys))
      |> Map.merge(resolved_conflicts)

    %__MODULE__{
      dots: new_dots,
      keys: new_keys,
      value: new_val
    }
  end

  def read(%{value: value}) do
    Enum.flat_map(value, fn {key, values} ->
      Enum.map(values, fn {val, _c} -> {key, val} end)
    end)
    |> Enum.reduce(%{}, fn {key, {val, ts}}, map ->
      Map.update(map, key, {val, ts}, fn
        {_val1, ts1} = newer_value when ts1 > ts -> newer_value
        _ -> {val, ts}
      end)
    end)
    |> Map.new(fn {key, {val, _ts}} -> {key, val} end)
  end

  defp aw_set_add(i, el, {aw_set, c}) do
    d = next_dot(i, c)
    {%{el => [d]}, [d | Map.get(aw_set, el, [])]}
  end

  def dot_set_join(%{value: s1, dots: c1}, %{value: s2, dots: c2}, []) do
    s1 = MapSet.new(s1)
    s2 = MapSet.new(s2)

    new_s =
      [
        MapSet.intersection(s1, s2),
        MapSet.difference(s1, c2),
        MapSet.difference(s2, c1)
      ]
      |> Enum.reduce(&MapSet.union/2)

    # we aren't going to end up using this anyways
    new_c = []

    %__MODULE__{value: new_s}
  end

  defp apply_op(op, key, %{value: m, dots: c}) do
    {val, c_p} = op.(Map.get(m, key, %{}), c)

    %__MODULE__{
      value: %{key => val},
      dots: MapSet.new(c_p),
      keys: MapSet.new([key])
    }
  end

  defp next_dot(i, c) do
    {_i, max} =
      Enum.max_by(
        c,
        fn
          {^i, x} -> x
          _ -> 0
        end,
        fn -> {i, 0} end
      )

    {i, max + 1}
  end
end
