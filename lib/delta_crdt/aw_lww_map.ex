defmodule DeltaCrdt.AWLWWMap do
  defstruct keys: MapSet.new(),
            dots: MapSet.new(),
            value: %{}

  require Logger

  def new(), do: %__MODULE__{}

  defmodule Dots do
    def compress(dots = %MapSet{}) do
      Enum.reduce(dots, %{}, fn {c, i}, dots_map ->
        Map.update(dots_map, c, i, fn
          x when x > i -> x
          _x -> i
        end)
      end)
    end

    def decompress(dots = %MapSet{}), do: dots

    def decompress(dots) do
      Enum.flat_map(dots, fn {i, x} ->
        Enum.map(1..x, fn y -> {i, y} end)
      end)
    end

    def next_dot(i, c = %MapSet{}) do
      Logger.warn("inefficient next_dot computation")
      next_dot(i, compress(c))
    end

    def next_dot(i, c) do
      {i, Map.get(c, i, 0) + 1}
    end

    def union(dots1 = %MapSet{}, dots2 = %MapSet{}) do
      MapSet.union(dots1, dots2)
    end

    def union(dots1 = %MapSet{}, dots2), do: union(dots2, dots1)

    def union(dots1, dots2) do
      Enum.reduce(dots2, dots1, fn {c, i}, dots_map ->
        Map.update(dots_map, c, i, fn
          x when x > i -> x
          _x -> i
        end)
      end)
    end

    def difference(dots1 = %MapSet{}, dots2 = %MapSet{}) do
      MapSet.difference(dots1, dots2)
    end

    def difference(_dots1, dots2 = %MapSet{}), do: raise("this should not happen")

    def difference(dots1, dots2) do
      Enum.reject(dots1, fn dot ->
        member?(dots2, dot)
      end)
      |> MapSet.new()
    end

    def member?(dots = %MapSet{}, dot = {_, _}) do
      MapSet.member?(dots, dot)
    end

    def member?(dots, {i, x}) do
      Map.get(dots, i, 0) >= x
    end

    def strict_expansion?(dots = %MapSet{}, delta_dots) do
      raise "we should not get here"
    end

    def strict_expansion?(dots, delta_dots) do
      Enum.all?(min_dots(delta_dots), fn {i, x} ->
        Map.get(dots, i, 0) + 1 >= x
      end)
    end

    def min_dots(dots = %MapSet{}) do
      Enum.reduce(dots, %{}, fn {i, x}, min ->
        Map.update(min, i, x, fn
          min when min < x -> min
          _min -> x
        end)
      end)
    end

    def min_dots(dots) do
      %{}
    end
  end

  def add(key, value, i, state) do
    rem = remove(key, i, state)

    add =
      fn aw_set, context ->
        aw_set_add(i, {value, System.system_time(:nanosecond)}, {aw_set, context})
      end
      |> apply_op(key, state)

    case MapSet.size(rem.dots) do
      0 -> add
      _ -> join(rem, add)
    end
  end

  def compress_dots(state) do
    %{state | dots: Dots.compress(state.dots)}
  end

  defp aw_set_add(i, el, {aw_set, c}) do
    d = Dots.next_dot(i, c)
    {%{el => MapSet.new([d])}, MapSet.put(Map.get(aw_set, el, MapSet.new()), d)}
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

  def expansion?(%{value: values} = d, state) when map_size(values) == 0 do
    # check remove expansion
    case Enum.to_list(d.dots) do
      [] ->
        false

      [dot] ->
        Dots.member?(state.dots, dot) && !MapSet.disjoint?(d.keys, state.keys) &&
          Map.take(state.value, d.keys)
          |> Enum.any?(fn {_k, val} ->
            Enum.any?(val, fn
              {_v, dots} -> MapSet.member?(dots, dot)
            end)
          end)
    end
  end

  def expansion?(d, state) do
    # check add expansion

    case Enum.to_list(d.dots) do
      [] -> false
      [dot] -> !Dots.member?(state.dots, dot)
    end
  end

  defp dots_to_deltas(%{value: val}) do
    Enum.flat_map(val, fn {key, dot_map} ->
      Enum.flat_map(dot_map, fn {_key, dots} ->
        Enum.map(dots, fn dot -> {dot, key} end)
      end)
    end)
    |> Map.new()
  end

  def join_decomposition(delta) do
    d2d = dots_to_deltas(delta)

    Enum.map(Dots.decompress(delta.dots), fn dot ->
      case Map.get(d2d, dot) do
        nil ->
          %__MODULE__{
            dots: MapSet.new([dot]),
            keys: delta.keys,
            value: %{}
          }

        key ->
          dots = Map.get(delta.value, key)

          %__MODULE__{
            dots: MapSet.new([dot]),
            keys: MapSet.new([key]),
            value: %{key => dots}
          }
      end
    end)
  end

  def join(delta1, delta2) do
    new_dots = Dots.union(delta1.dots, delta2.dots)
    new_keys = MapSet.union(delta1.keys, delta2.keys)

    join_or_maps(delta1, delta2, [:join_or_maps, :join_dot_sets])
    |> Map.put(:dots, new_dots)
    |> Map.put(:keys, new_keys)
  end

  def join_or_maps(delta1, delta2, nested_joins) do
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

  def join_dot_sets(%{value: s1, dots: c1}, %{value: s2, dots: c2}, []) do
    s1 = MapSet.new(s1)
    s2 = MapSet.new(s2)

    new_s =
      [
        MapSet.intersection(s1, s2),
        Dots.difference(s1, c2),
        Dots.difference(s2, c1)
      ]
      |> Enum.reduce(&MapSet.union/2)

    %__MODULE__{value: new_s}
  end

  def read(%{value: values}) do
    Map.new(values, fn {key, values} ->
      {{val, _ts}, _c} = Enum.max_by(values, fn {{_val, ts}, _c} -> ts end)
      {key, val}
    end)
  end
end
