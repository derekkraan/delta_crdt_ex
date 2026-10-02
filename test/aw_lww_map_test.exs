defmodule NewAWLWWMapTest do
  use ExUnit.Case
  use ExUnitProperties

  alias DeltaCrdt.AWLWWMap

  test "can add and read a value" do
    assert %{1 => 2} =
             AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
             |> AWLWWMap.read()
  end

  test "can join two adds" do
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    add2 = AWLWWMap.add(2, 2, :foo_node, add1)

    assert %{1 => 2, 2 => 2} =
             AWLWWMap.join(add1, add2, [1, 2])
             |> AWLWWMap.read()
  end

  test "can add multiple values and only read one" do
    new = AWLWWMap.new()
    add1 = AWLWWMap.add(1, 2, :foo_node, new)
    add2 = AWLWWMap.add(2, 3, :foo_node, add1)
    state = AWLWWMap.join(add1, add2, [1, 2])

    assert %{1 => 2} = AWLWWMap.read(state, 1)
  end

  test "can remove elements" do
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    remove1 = AWLWWMap.remove(1, :foo_node, add1)

    assert %{} =
             AWLWWMap.join(add1, remove1, [1])
             |> AWLWWMap.read()
  end

  test "can resolve conflicts" do
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    add2 = AWLWWMap.add(1, 3, :foo_node, add1)

    # TODO assert that the state doesn't include anything about value 2

    assert %{1 => 3} =
             AWLWWMap.join(add1, add2, [1])
             |> AWLWWMap.read()
  end

  test "can compute actual dots present" do
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    change1 = AWLWWMap.add(1, 3, :foo_node, add1)

    final = AWLWWMap.join(add1, change1, [1])

    assert 1 = map_size(AWLWWMap.compress_dots(final) |> Map.get(:dots))
  end

  describe "joining a partial delta" do
    setup do
      new = AWLWWMap.compress_dots(AWLWWMap.new())

      sender =
        Enum.reduce(1..3, new, fn key, state ->
          AWLWWMap.join(state, AWLWWMap.add(key, key, :sender, state), [key])
        end)

      partial = %{sender | value: Map.take(sender.value, [3])} |> Map.put(:partial, true)

      [new: new, sender: sender, receiver: AWLWWMap.join(new, partial, [3])]
    end

    test "only adopts the dots of the entries it received", context do
      assert %{3 => 3} == AWLWWMap.read(context.receiver)
      assert %{} == context.receiver.dots
      assert MapSet.new([{:sender, 3}]) == context.receiver.cloud
    end

    test "syncing back doesn't remove entries the receiver never got", context do
      delta = %{context.receiver | value: Map.take(context.receiver.value, [1, 2])}

      assert %{1 => 1, 2 => 2, 3 => 3} ==
               AWLWWMap.join(context.sender, delta, [1, 2]) |> AWLWWMap.read()
    end

    test "a local remove afterwards doesn't claim unseen dots", context do
      receiver =
        AWLWWMap.join(context.receiver, AWLWWMap.remove(3, :receiver, context.receiver), [3])

      assert %{} == receiver.dots
      delta = %{receiver | value: %{}}

      assert %{1 => 1, 2 => 2} ==
               AWLWWMap.join(context.sender, delta, [1, 2, 3]) |> AWLWWMap.read()
    end

    test "removes entries under the sent keys that the sender removed", context do
      receiver = AWLWWMap.join(context.new, context.sender, [1, 2, 3])
      sender = AWLWWMap.join(context.sender, AWLWWMap.remove(1, :sender, context.sender), [1])
      partial = %{sender | value: Map.take(sender.value, [1])} |> Map.put(:partial, true)

      assert %{2 => 2, 3 => 3} == AWLWWMap.join(receiver, partial, [1]) |> AWLWWMap.read()
    end

    test "a full sync afterwards compacts the cloud", context do
      receiver = AWLWWMap.join(context.receiver, context.sender, [1, 2])

      assert %{sender: 3} == receiver.dots
      assert MapSet.new() == receiver.cloud
    end
  end

  property "arbitrary add and remove sequence results in correct map" do
    operation_gen =
      ExUnitProperties.gen all op <- StreamData.member_of([:add, :remove]),
                               node_id <- term(),
                               key <- term(),
                               value <- term() do
        {op, key, value, node_id}
      end

    check all operations <- list_of(operation_gen) do
      actual_result =
        operations
        |> Enum.reduce(AWLWWMap.new(), fn
          {:add, key, val, node_id}, map ->
            AWLWWMap.add(key, val, node_id, map)
            |> AWLWWMap.join(map, [key])

          {:remove, key, _val, node_id}, map ->
            AWLWWMap.remove(key, node_id, map)
            |> AWLWWMap.join(map, [key])
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
end
