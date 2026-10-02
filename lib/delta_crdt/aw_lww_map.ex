defmodule DeltaCrdt.AWLWWMap do
  # `dots` is the causal context: compressed to `%{node_id => max_counter}` in a state, or an
  # exact `MapSet` of dots in a delta. `cloud` holds the observed dots that can't be
  # compressed yet, because a lower dot of the same node hasn't been observed.
  defstruct dots: MapSet.new(),
            cloud: MapSet.new(),
            value: %{}

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
      Logger.warning("inefficient next_dot computation")
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

    def difference(dots1 = %MapSet{}, dots2 = %MapSet{}, _cloud) do
      MapSet.difference(dots1, dots2)
    end

    def difference(_dots1, _dots2 = %MapSet{}, _cloud), do: raise("this should not happen")

    def difference(dots1, dots2, cloud) do
      Enum.reject(dots1, fn dot ->
        member?(dots2, dot) or MapSet.member?(cloud, dot)
      end)
      |> MapSet.new()
    end

    # Adds exact dots to a compressed context. A dot only advances its node's counter when
    # it's the next one; otherwise it goes in the cloud, so we never claim to have
    # observed dots we haven't.
    def compact(dots, cloud, new_dots) do
      Enum.reduce(new_dots, {dots, cloud}, fn {i, x} = dot, {dots, cloud} ->
        max = Map.get(dots, i, 0)

        cond do
          x <= max -> {dots, cloud}
          x == max + 1 -> extend(Map.put(dots, i, x), MapSet.delete(cloud, dot), i)
          true -> {dots, MapSet.put(cloud, dot)}
        end
      end)
    end

    defp extend(dots, cloud, i) do
      next = {i, Map.fetch!(dots, i) + 1}

      if MapSet.member?(cloud, next) do
        extend(Map.put(dots, i, elem(next, 1)), MapSet.delete(cloud, next), i)
      else
        {dots, cloud}
      end
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
        aw_set_add(i, {value, System.monotonic_time(:nanosecond)}, {aw_set, context})
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
    {%{el => MapSet.new([d])}, MapSet.put(Map.get(aw_set, el, MapSet.new()), d)}
  end

  defp apply_op(op, key, %{value: m, dots: c}) do
    {val, c_p} = op.(Map.get(m, key, %{}), c)

    %__MODULE__{
      dots: MapSet.new(c_p),
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
      value: %{}
    }
  end

  def clear(_i, state) do
    Map.put(state, :value, %{})
  end

  @doc false
  def join(delta1, delta2, keys) do
    {new_dots, new_cloud} = join_contexts(delta1, delta2, keys)

    join_or_maps(delta1, delta2, [:join_or_maps, :join_dot_sets], keys)
    |> Map.put(:dots, new_dots)
    |> Map.put(:cloud, new_cloud)
  end

  # A partial delta carries the sender's whole causal context but only the entries under
  # `keys`. That context decides which of our entries under `keys` were removed, but
  # adopting it would claim we observed entries under other keys that we never received
  # (and would remove them everywhere on the next sync). Only record the received dots.
  defp join_contexts(delta1, %{partial: true} = delta2, keys) do
    received_dots =
      for key <- keys, {_el, dots} <- Map.get(delta2.value, key, %{}), dot <- dots, do: dot

    Dots.compact(delta1.dots, cloud(delta1), received_dots)
  end

  defp join_contexts(%{dots: dots1 = %MapSet{}}, %{dots: dots2 = %MapSet{}}, _keys) do
    {MapSet.union(dots1, dots2), MapSet.new()}
  end

  defp join_contexts(delta1 = %{dots: %MapSet{}}, delta2, keys) do
    join_contexts(delta2, delta1, keys)
  end

  defp join_contexts(delta1, %{dots: dots2 = %MapSet{}}, _keys) do
    Dots.compact(delta1.dots, cloud(delta1), dots2)
  end

  defp join_contexts(delta1, delta2, _keys) do
    Dots.compact(
      Dots.union(delta1.dots, delta2.dots),
      MapSet.new(),
      MapSet.union(cloud(delta1), cloud(delta2))
    )
  end

  # states persisted by an older version have no cloud
  defp cloud(state), do: Map.get(state, :cloud, MapSet.new())

  @doc false
  def join_or_maps(delta1, delta2, nested_joins, keys) do
    resolved_conflicts =
      Enum.flat_map(keys, fn key ->
        sub_delta1 = Map.put(delta1, :value, Map.get(delta1.value, key, %{}))

        sub_delta2 = Map.put(delta2, :value, Map.get(delta2.value, key, %{}))

        keys =
          (Map.keys(sub_delta1.value) ++ Map.keys(sub_delta2.value))
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
      |> Map.new()

    new_val =
      Map.drop(delta1.value, keys)
      |> Map.merge(Map.drop(delta2.value, keys))
      |> Map.merge(resolved_conflicts)

    %__MODULE__{
      value: new_val
    }
  end

  @doc false
  def join_dot_sets(delta1 = %{value: s1, dots: c1}, delta2 = %{value: s2, dots: c2}, [], _keys) do
    s1 = MapSet.new(s1)
    s2 = MapSet.new(s2)

    new_s =
      [
        MapSet.intersection(s1, s2),
        Dots.difference(s1, c2, cloud(delta2)),
        Dots.difference(s2, c1, cloud(delta1))
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

  def read(_crdt, []), do: %{}

  def read(%{value: values}, keys) when is_list(keys) do
    read(%{value: Map.take(values, keys)})
  end

  def read(crdt, key) do
    read(crdt, [key])
  end
end
