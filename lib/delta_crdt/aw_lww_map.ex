defmodule DeltaCrdt.AWLWWMap do
  defstruct dots: MapSet.new(),
            value: MerkleMap.new()

  require Logger

  @doc false
  def new(), do: %__MODULE__{}

  defmodule Dots do
    @moduledoc false

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

    def difference(_dots1, _dots2 = %MapSet{}), do: raise("this should not happen")

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

    def strict_expansion?(_dots = %MapSet{}, _delta_dots) do
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

    def min_dots(_dots) do
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
      _ -> join(rem, add, [key])
    end
  end

  @doc false
  def compress_dots(state) do
    %{state | dots: Dots.compress(state.dots)}
  end

  defp aw_set_add(i, el, {aw_set, c}) do
    d = Dots.next_dot(i, c)

    {MerkleMap.new(%{el => MapSet.new([d])}),
     MapSet.put(MerkleMap.get(aw_set, el, MapSet.new()), d)}
  end

  defp apply_op(op, key, %{value: m, dots: c}) do
    {val, c_p} = op.(MerkleMap.get(m, key, MerkleMap.new()), c)

    %__MODULE__{
      dots: MapSet.new(c_p),
      value: MerkleMap.new(%{key => val})
    }
  end

  def remove(key, _i, state) do
    %{value: val} = state

    to_remove_dots =
      case MerkleMap.fetch(val, key) do
        {:ok, value} -> Enum.flat_map(value, fn {_val, to_remove_dots} -> to_remove_dots end)
        :error -> []
      end

    %__MODULE__{
      dots: MapSet.new(to_remove_dots),
      value: MerkleMap.new()
    }
  end

  def clear(_i, state) do
    Map.put(state, :value, MerkleMap.new())
  end

  @doc false
  def join(delta1, delta2, keys) do
    new_dots = Dots.union(delta1.dots, delta2.dots)

    join_or_maps(delta1, delta2, [:join_or_maps, :join_dot_sets], keys)
    |> Map.put(:dots, new_dots)
  end

  @doc false
  def join_or_maps(delta1, delta2, nested_joins, keys) do
    resolved_conflicts =
      Enum.flat_map(keys, fn key ->
        sub_delta1 = Map.put(delta1, :value, MerkleMap.get(delta1.value, key, MerkleMap.new()))

        sub_delta2 = Map.put(delta2, :value, MerkleMap.get(delta2.value, key, MerkleMap.new()))

        keys =
          (MerkleMap.keys(sub_delta1.value) ++ MerkleMap.keys(sub_delta2.value))
          |> Enum.uniq()

        [next_join | other_joins] = nested_joins

        %{value: new_sub} =
          apply(__MODULE__, next_join, [sub_delta1, sub_delta2, other_joins, keys])

        if Enum.empty?(new_sub) do
          []
        else
          [{key, new_sub}]
        end
      end)
      |> MerkleMap.new()

    new_val =
      MerkleMap.drop(delta1.value, keys)
      |> MerkleMap.merge(MerkleMap.drop(delta2.value, keys))
      |> MerkleMap.merge(resolved_conflicts)

    %__MODULE__{
      value: new_val
    }
  end

  @doc false
  def join_dot_sets(%{value: s1, dots: c1}, %{value: s2, dots: c2}, [], _keys) do
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
    MerkleMap.new(values, fn {key, values} -> {key, compute_value(values)} end)
  end

  defp compute_value(nil), do: nil

  defp compute_value(values) do
    {{val, _ts}, _c} = Enum.max_by(values, fn {{_val, ts}, _c} -> ts end)
    val
  end

  def read(%{value: values}, keys) when is_list(keys) do
    read(%{value: MerkleMap.take(values, keys)})
  end

  def read(crdt, key) do
    read(crdt, [key])
  end

  def get(%{value: values}, key) do
    compute_value(MerkleMap.get(values, key))
  end
end
