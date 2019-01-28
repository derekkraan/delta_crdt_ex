defmodule NewAWLWWMapTest do
  use ExUnit.Case

  test "can add and read a value" do
    assert %{1 => 2} =
             AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
             |> AWLWWMap.read()
  end

  test "can join two adds" do
    # |> IO.inspect()
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    # |> IO.inspect()
    add2 = AWLWWMap.add(2, 2, :foo_node, add1)

    assert %{1 => 2, 2 => 2} =
             AWLWWMap.join(add1, add2)
             |> AWLWWMap.read()
  end

  test "can remove elements" do
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    remove1 = AWLWWMap.remove(1, :foo_node, add1)

    assert %{} =
             AWLWWMap.join(add1, remove1)
             |> AWLWWMap.read()
  end

  test "can resolve conflicts" do
    add1 = AWLWWMap.add(1, 2, :foo_node, AWLWWMap.new())
    add2 = AWLWWMap.add(1, 3, :foo_node, add1)

    # TODO assert that the state doesn't include anything about value 2

    assert %{1 => 3} =
             AWLWWMap.join(add1, add2)
             |> AWLWWMap.read()
  end
end
