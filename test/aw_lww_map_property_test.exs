defmodule AWLWWMapPropertyTest do
  alias DeltaCrdt.AWLWWMap
  use ExUnit.Case, async: true
  use ExUnitProperties

  setup do
    operation_gen =
      ExUnitProperties.gen all(
                             op <- StreamData.member_of([:add, :remove]),
                             node_id <- term(),
                             key <- term(),
                             value <- term()
                           ) do
        {op, key, value, node_id}
      end

    [operation_gen: operation_gen]
  end

  describe ".add/4" do
    property "can add an element" do
      check all(
              key <- term(),
              val <- term(),
              node_id <- term()
            ) do
        assert %{key => val} ==
                 AWLWWMap.join(
                   AWLWWMap.compress_dots(AWLWWMap.new()),
                   AWLWWMap.add(key, val, node_id, AWLWWMap.compress_dots(AWLWWMap.new())),
                   [key]
                 )
                 |> AWLWWMap.read()
      end
    end
  end

  property "arbitrary add and remove sequence results in correct map", context do
    check all(operations <- list_of(context.operation_gen)) do
      actual_result =
        operations
        |> Enum.reduce(AWLWWMap.compress_dots(AWLWWMap.new()), fn
          {:add, key, val, node_id}, map ->
            AWLWWMap.join(map, AWLWWMap.add(key, val, node_id, map), [key])

          {:remove, key, _val, node_id}, map ->
            AWLWWMap.join(map, AWLWWMap.remove(key, node_id, map), [key])
        end)
        |> AWLWWMap.read()

      correct_result =
        operations
        |> Enum.reduce(%{}, fn
          {:add, key, value, _node_id}, map ->
            Map.put(map, key, value)

          {:remove, key, _value, _node_id}, map ->
            Map.delete(map, key)
        end)

      assert actual_result == correct_result
    end
  end

  describe ".remove/3" do
    property "can remove an element" do
      check all(
              key <- term(),
              val <- term(),
              node_id <- term()
            ) do
        crdt = AWLWWMap.compress_dots(AWLWWMap.new())
        crdt = AWLWWMap.join(crdt, AWLWWMap.add(key, val, node_id, crdt), [key])

        crdt =
          AWLWWMap.join(crdt, AWLWWMap.remove(key, node_id, crdt), [key])
          |> AWLWWMap.read()

        assert %{} == crdt
      end
    end
  end
end
