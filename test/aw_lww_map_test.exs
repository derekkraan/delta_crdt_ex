defmodule AWLWWMapTest do
  alias DeltaCrdt.{AWLWWMap, SemiLattice}
  use ExUnit.Case, async: true
  use ExUnitProperties

  setup do
    operation_gen =
      ExUnitProperties.gen all op <- StreamData.member_of([:add, :remove]),
                               node_id <- term(),
                               key <- term(),
                               value <- term() do
        {op, key, value, node_id}
      end

    [operation_gen: operation_gen]
  end

  describe ".add/4" do
    property "can add an element" do
      check all key <- term(),
                val <- term(),
                node_id <- term() do
        assert %{key => val} ==
                 SemiLattice.join(AWLWWMap.new(), AWLWWMap.add(key, val, node_id, AWLWWMap.new()))
                 |> AWLWWMap.read()
      end
    end
  end

  property "arbitrary add and remove sequence results in correct map", context do
    check all operations <- list_of(context.operation_gen) do
      actual_result =
        operations
        |> Enum.reduce(AWLWWMap.new(), fn
          {:add, key, val, node_id}, map ->
            SemiLattice.join(map, AWLWWMap.add(key, val, node_id, map))

          {:remove, key, val, node_id}, map ->
            SemiLattice.join(map, AWLWWMap.remove(key, node_id, map))
        end)
        |> AWLWWMap.read()

      correct_result =
        operations
        |> Enum.reduce(%{}, fn
          {:add, key, value, node_id}, map ->
            Map.put(map, key, value)

          {:remove, key, value, node_id}, map ->
            Map.delete(map, key)
        end)

      assert actual_result == correct_result
    end
  end

  describe ".remove/3" do
    property "can remove an element" do
      check all key <- term(),
                val <- term(),
                node_id <- term() do
        crdt = AWLWWMap.new()
        crdt = SemiLattice.join(crdt, AWLWWMap.add(key, val, node_id, crdt))

        crdt =
          SemiLattice.join(crdt, AWLWWMap.remove(key, node_id, crdt))
          |> AWLWWMap.read()

        assert %{} == crdt
      end
    end
  end

  describe ".clear/2" do
    property "removes all elements from the map", context do
      check all ops <- list_of(context.operation_gen),
                node_id <- term() do
        populated_map =
          Enum.reduce(ops, AWLWWMap.new(), fn
            {:add, key, val, node_id}, map ->
              AWLWWMap.add(key, val, node_id, map)
              |> SemiLattice.join(map)

            {:remove, key, _val, node_id}, map ->
              AWLWWMap.remove(key, node_id, map)
              |> SemiLattice.join(map)
          end)

        cleared_map =
          AWLWWMap.clear(node_id, populated_map)
          |> SemiLattice.join(populated_map)
          |> AWLWWMap.read()

        assert %{} == cleared_map
      end
    end
  end
end
