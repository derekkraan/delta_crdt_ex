defmodule DeltaCrdt.AWLWWMap do
  defstruct keys: MapSet.new(),
            dots: MapSet.new(),
            value: %{}

  def new(), do: %__MODULE__{}

  def add(key, value, i, state) do
    rem = remove(key, i, state)

    fn aw_set, context ->
      aw_set_add(i, {value, System.system_time(:nanosecond)}, {aw_set, context})
    end
    |> apply_op(key, state)
    |> join(rem)
  end

  defp aw_set_add(i, el, {aw_set, c}) do
    d = next_dot(i, c)
    {%{el => [d]}, [d | Map.get(aw_set, el, [])]}
  end

  defp apply_op(op, key, %{value: m, dots: c}) do
    {val, c_p} = op.(Map.get(m, key, %{}), c)

    %__MODULE__{
      dots: MapSet.new(c_p),
      keys: MapSet.new([key]),
      value: %{key => val}
    }
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

  def expansion?(%{value: value} = d, state) when map_size(value) == 0 do
    # check remove expansion
    case Enum.to_list(d.dots) do
      [] -> false
      [dot] -> MapSet.member?(state.dots, dot) && !MapSet.disjoint?(state.keys, d.keys)
    end
  end

  def expansion?(d, state) do
    # check add expansion
    case Enum.to_list(d.dots) do
      [] -> false
      [dot] -> !MapSet.member?(state.dots, dot)
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

  def join(delta1, delta2) do
    new_dots = MapSet.union(delta1.dots, delta2.dots)
    new_keys = MapSet.union(delta1.keys, delta2.keys)

    join_or_map(delta1, delta2, [:join_or_map, :dot_set_join])
    |> Map.put(:dots, new_dots)
    |> Map.put(:keys, new_keys)
  end

  def join_or_map(delta1, delta2, nested_joins \\ [:join, :dot_set_join]) do
    val1 = delta1.value
    val2 = delta2.value

    all_intersecting = Enum.empty?(delta1.keys) || Enum.empty?(delta2.keys)

    intersecting_keys =
      if all_intersecting do
        # "no keys" means that we have to check every key
        MapSet.new(Map.keys(val1) ++ Map.keys(val2))
      else
        MapSet.intersection(delta1.keys, delta2.keys)
      end

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
      if all_intersecting do
        resolved_conflicts
      else
        Map.drop(delta1.value, intersecting_keys)
        |> Map.merge(Map.drop(delta2.value, intersecting_keys))
        |> Map.merge(resolved_conflicts)
      end

    %__MODULE__{
      value: new_val
    }
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
      |> Enum.to_list()

    %__MODULE__{value: new_s}
  end

  def read(%{value: values}) do
    Map.new(values, fn {key, values} ->
      {{val, _ts}, _c} = Enum.max_by(values, fn {{_val, ts}, _c} -> ts end)
      {key, val}
    end)
  end

  defmodule BinarySearch do
    def binary_search(fun, min \\ 1, max \\ 100) when min <= max do
      upper_bound = find_upper_bound(fun, max)
      find_value(fun, min, upper_bound)
    end

    defp find_upper_bound(fun, max) do
      case fun.(max) do
        x when x < 0 ->
          find_upper_bound(fun, max * 2)

        x when x > 0 ->
          max
      end
    end

    defp find_value(_fun, min, min) do
      min
    end

    defp find_value(fun, min, max) do
      attempt = trunc(min + (max - min) / 2)

      case fun.(attempt) do
        x when x < 0 ->
          find_value(fun, attempt + 1, max)

        x when x > 0 ->
          find_value(fun, min, attempt)
      end
    end
  end

  defp next_dot(i, c) do
    next_max =
      BinarySearch.binary_search(fn x ->
        if MapSet.member?(c, {i, x}) do
          -1
        else
          1
        end
      end)

    {i, next_max}
  end
end
