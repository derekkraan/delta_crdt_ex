defmodule AWLWWMapTest do
  alias DeltaCrdt.AWLWWMap
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
                 AWLWWMap.join(AWLWWMap.new(), AWLWWMap.add(key, val, node_id, AWLWWMap.new()))
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
            AWLWWMap.join(map, AWLWWMap.add(key, val, node_id, map))

          {:remove, key, _val, node_id}, map ->
            AWLWWMap.join(map, AWLWWMap.remove(key, node_id, map))
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
      check all key <- term(),
                val <- term(),
                node_id <- term() do
        crdt = AWLWWMap.new()
        crdt = AWLWWMap.join(crdt, AWLWWMap.add(key, val, node_id, crdt))

        crdt =
          AWLWWMap.join(crdt, AWLWWMap.remove(key, node_id, crdt))
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
              |> AWLWWMap.join(map)

            {:remove, key, _val, node_id}, map ->
              AWLWWMap.remove(key, node_id, map)
              |> AWLWWMap.join(map)
          end)

        cleared_map =
          AWLWWMap.clear(node_id, populated_map)
          |> AWLWWMap.join(populated_map)
          |> AWLWWMap.read()

        assert %{} == cleared_map
      end
    end
  end

  describe ".start_link/2" do
    test "starts a causal CRDT process" do
    end
  end

  describe ".join_decomposition/1" do
    property "join decomposition has one dot per decomposed delta" do
      check all ops <- list_of(AWLWWMapProperty.random_operation()) do
        # make 1 delta
        joined_delta =
          Enum.reduce(ops, AWLWWMap.new(), fn op, st ->
            delta = op.(st)
            AWLWWMap.join(st, delta)
          end)

        # decompose delta
        decomposed_ops = AWLWWMap.join_decomposition(joined_delta)

        Enum.each(decomposed_ops, fn op ->
          assert 1 = MapSet.size(op.dots)
        end)
      end
    end

    property "join decomposition when joined returns itself" do
      check all ops <- list_of(AWLWWMapProperty.random_operation()) do
        joined_delta =
          Enum.reduce(ops, AWLWWMap.new(), fn op, st ->
            delta = op.(st)
            AWLWWMap.join(st, delta)
          end)

        decomposed_ops = AWLWWMap.join_decomposition(joined_delta)

        rejoined_delta = Enum.reduce(decomposed_ops, AWLWWMap.new(), &AWLWWMap.join/2)

        assert Map.equal?(AWLWWMap.read(rejoined_delta), AWLWWMap.read(joined_delta))
      end
    end
  end

  describe ".expansion?/2" do
    property "no operation is a strict expansion of itself" do
      check all op <- AWLWWMapProperty.random_operation() do
        op = op.(AWLWWMap.new())

        assert false == AWLWWMap.expansion?(op, op)
      end
    end

    property "operation can be applied and then is no longer strict expansion" do
      check all [op1, op2] <- list_of(AWLWWMapProperty.random_operation(), length: 2) do
        op1 = op1.(AWLWWMap.new())
        op2 = op2.(op1)
        state = AWLWWMap.join(op1, op2)

        Enum.each(AWLWWMap.join_decomposition(op2), fn op ->
          assert false == AWLWWMap.expansion?(op, state)
        end)
      end
    end
  end
end
