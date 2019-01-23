defmodule DeltaCrdt.AWLWWMap do
  @opaque crdt_state :: CausalDotMap.t()
  @opaque crdt_delta :: CausalDotMap.t()
  @type key :: term()
  @type value :: term()
  @type node_id :: term()
  @moduledoc """
  An add-wins last-write-wins map.

  This CRDT is an add-wins last-write-wins map. This means:

  * The data structure is of a map. So you can store the following values:

  ```
  %{key: "value"}
  %{"1" => %{another_map: "what!"}}
  %{123 => {:a, :tuple}}
  ```

  * Both keys and values are of type `term()` (aka `any()`).

  * Add-wins means that if there is a conflict between an add and a remove operation, the add operation will win out. This is in contrast to remove-wins, where the remove operation would win.

  * Last-write-wins means that if there is a conflict between two write operations, the latest (as marked with a timestamp) will win. Underwater, every delta contains a timestamp which is used to resolve the conflicts.
  """

  alias DeltaCrdt.{CausalDotMap, AWSet, ORMap}

  @doc "Convenience function to create an empty add-wins last-write-wins map"
  @spec new() :: crdt_state()
  def new(), do: %CausalDotMap{}

  @doc "Add (or overwrite) a key-value pair to the map"
  @spec add(key :: key(), val :: value(), i :: node_id(), crdt_state()) :: crdt_delta()
  def add(key, val, i, map) do
    {AWSet, :add, [{val, System.system_time(:nanosecond)}]}
    |> ORMap.apply(key, i, map)
  end

  @doc "Remove a key and it's corresponding value from the map"
  @spec remove(key :: key(), i :: node_id(), crdt_state()) :: crdt_delta()
  def remove(key, i, map), do: ORMap.remove(key, i, map)

  @doc "Remove all key-value pairs from the map"
  @spec clear(node_id(), crdt_state()) :: crdt_delta()
  def clear(i, map), do: ORMap.clear(i, map)

  @doc """
  Read the state of the map

  **Note: this operation is expensive, so it's best not to call this more often than necessary.**
  """
  @spec read(map :: crdt_state()) :: map()
  def read(%{state: map}) do
    Map.new(map, fn {key, values} ->
      {val, _ts} = Enum.max_by(Map.keys(values.state), fn {_val, ts} -> ts end)
      {key, val}
    end)
  end

  def strict_expansion?(state, delta) do
    case DeltaCrdt.SemiLattice.bottom?(delta) do
      true ->
        check_remove_expansion(state, delta)

      false ->
        check_add_expansion(state, delta)
    end
  end

  defp check_add_expansion(state, delta) do
    case MapSet.to_list(delta.causal_context.dots) do
      [] ->
        false

      [{x, y}] ->
        Map.get(state.causal_context.maxima, x, -1) < y
    end
  end

  defp check_remove_expansion(state, delta) do
    case MapSet.to_list(delta.causal_context.dots) do
      [] ->
        false

      [dot] ->
        Enum.filter(state.state, fn {key, _map} -> MapSet.member?(delta.keys, key) end)
        |> Enum.any?(fn {_key, dot_map} ->
          Enum.any?(dot_map.state, fn {_key, %{state: dot_set}} ->
            MapSet.member?(dot_set, dot)
          end)
        end)
    end
  end

  def join_decomposition(delta) do
    dots_to_deltas =
      Enum.flat_map(delta.state, fn {key, dot_map} ->
        Enum.flat_map(dot_map.state, fn {_key, %{state: dots}} ->
          Enum.map(dots, fn dot -> {dot, key} end)
        end)
      end)
      |> Map.new()

    Enum.map(delta.causal_context.dots, fn dot ->
      case Map.get(dots_to_deltas, dot) do
        nil ->
          %DeltaCrdt.CausalDotMap{
            causal_context: DeltaCrdt.CausalContext.new([dot]),
            state: %{},
            keys: delta.keys
          }

        key ->
          dots = Map.get(delta.state, key)

          %DeltaCrdt.CausalDotMap{
            causal_context: DeltaCrdt.CausalContext.new([dot]),
            state: %{key => dots},
            keys: MapSet.new([key])
          }
      end
    end)
  end

  def minimum_deltas(state, delta) do
    join_decomposition(delta)
    |> Enum.filter(fn d -> strict_expansion?(state, d) end)
  end
end
