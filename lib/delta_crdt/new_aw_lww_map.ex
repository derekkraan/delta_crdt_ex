defmodule AWLWWMap do
  defstruct keys: MapSet.new(),
            dots: MapSet.new(),
            value: {%{}, []}

  def new(), do: %__MODULE__{}

  def add(key, value, i, state) do
    fn aw_set, context ->
      aw_set_add(i, {value, System.system_time(:nanosecond)}, {aw_set, context})
    end
    |> apply_op(key, state)
  end

  def remove(key, _i, state) do
    %{value: {val, _dots}} = state

    to_remove_dots =
      case Map.fetch(val, key) do
        {:ok, value} -> Enum.flat_map(value, fn {_val, to_remove_dots} -> to_remove_dots end)
        :error -> []
      end

    %__MODULE__{
      dots: MapSet.new(to_remove_dots),
      keys: MapSet.new([key]),
      value: {%{}, to_remove_dots}
    }
  end

  def join(delta1, delta2, nested_joins \\ [:join, :dot_set_join]) do
    {val1, context1} = delta1.value
    {val2, context2} = delta2.value

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
          Map.put(delta1, :value, {Map.get(val1, key, %{}), context1})
          |> Map.put(:keys, MapSet.new())

        sub_delta2 =
          Map.put(delta2, :value, {Map.get(val2, key, %{}), context2})
          |> Map.put(:keys, MapSet.new())

        [next_join | other_joins] = nested_joins

        %{value: {new_sub, _}} =
          apply(__MODULE__, next_join, [sub_delta1, sub_delta2, other_joins])

        if Enum.empty?(new_sub) do
          []
        else
          [{key, new_sub}]
        end
      end)
      |> Map.new()

    new_val =
      Map.drop(val1, intersecting_keys)
      |> Map.merge(Map.drop(val2, intersecting_keys))
      |> Map.merge(resolved_conflicts)

    new_context = join_contexts(context1, context2)

    %__MODULE__{
      dots: new_dots,
      keys: new_keys,
      value: {new_val, new_context}
    }
  end

  defp join_contexts(c1, c2) do
    Enum.uniq(c1 ++ c2)
  end

  def read(%{value: {value, _}}) do
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

  def dot_set_join(%{value: {s1, c1}}, %{value: {s2, c2}}, []) do
    s1 = MapSet.new(s1)
    c1 = MapSet.new(c1)
    s2 = MapSet.new(s2)
    c2 = MapSet.new(c2)

    new_s =
      [
        MapSet.intersection(s1, s2),
        MapSet.difference(s1, c2),
        MapSet.difference(s2, c1)
      ]
      |> Enum.reduce(&MapSet.union/2)

    # we aren't going to end up using this anyways
    new_c = []

    %__MODULE__{value: {new_s, new_c}}
  end

  defp apply_op(op, key, %{value: {m, c}}) do
    {val, c_p} = op.(Map.get(m, key, %{}), c)

    %__MODULE__{
      value: {%{key => val}, c_p},
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
