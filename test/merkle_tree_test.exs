defmodule MerkleTreeTest do
  use ExUnit.Case
  use ExUnitProperties

  property "diff of itself is always empty" do
    check all key <- term(),
              value <- term() do
      map = %{key => value}
      tree = MerkleTree.from_map(map)
      assert [] = MerkleTree.diff(tree, tree)
    end
  end

  property "diff identifies missing key" do
    check all key <- term(),
              value <- term() do
      map = %{key => value}
      tree = MerkleTree.from_map(map)
      assert [key] = MerkleTree.diff(%MerkleTree{}, tree)
    end
  end

  # property "arbitrarily large map can still find one changed key" do
  #   tree =
  #     Map.new(1..1000, fn x -> {x, x * x} end)
  #     |> MerkleTree.from_map()

  #   check all key <- term(),
  #             value <- term() do
  #     new_tree = MerkleTree.put_in_tree(tree, {key, value})
  #     assert [key] = MerkleTree.diff(new_tree, tree)
  #   end
  # end

  test "init a merkle tree" do
    assert MerkleTree.put_in_tree(%MerkleTree{}, {"foo", "bar"})
           |> MerkleTree.put_in_tree({"bar", "baz"})
  end

  test "init a whole map" do
    assert MerkleTree.from_map(%{foo: "bar", bar: "baz"})
  end

  test "diffs maps" do
    m1 = MerkleTree.from_map(%{foo: "bar", food: "good"})
    m2 = MerkleTree.from_map(%{foo: "baz", food: "good", drink: "also good"})
    assert Enum.sort([:foo, :drink]) == Enum.sort(MerkleTree.diff(m1, m2))
  end

  test "remove a key" do
    m1 = MerkleTree.from_map(%{foo: "bar", bar: "baz"})
    m2 = MerkleTree.from_map(%{foo: "bar"})

    removed = MerkleTree.remove_key(m1, :bar)

    assert [] = MerkleTree.diff(m2, removed)
    assert m2.hash == removed.hash
  end

  test "identical?" do
    tree_one = MerkleTree.put_in_tree(%MerkleTree{}, {"foo", "bar"})
    assert MerkleTree.identical?(tree_one, tree_one)

    tree_two = MerkleTree.put_in_tree(%MerkleTree{}, {"foo", "baz"})
    refute MerkleTree.identical?(tree_one, tree_two)
  end

  test "show diff" do
    tree_one = MerkleTree.put_in_tree(%MerkleTree{}, {"foo", "bar"})
    assert [] = MerkleTree.diff(tree_one, tree_one)
    tree_two = MerkleTree.put_in_tree(%MerkleTree{}, {"foo", "baz"})
    assert ["foo"] = MerkleTree.diff(tree_one, tree_two)
    tree_three = MerkleTree.put_in_tree(tree_one, {"bar", "baz"})

    assert ["bar"] = MerkleTree.diff(tree_one, tree_three)
    assert Enum.sort(["foo", "bar"]) == Enum.sort(MerkleTree.diff(tree_two, tree_three))
  end

  # test "can calculate partial diff from partial tree" do
  #   tree_one = MerkleTree.from_map(%{foo: "bar"})
  #   tree_two = MerkleTree.from_map(%{foo: "baz"})

  #   assert partial = MerkleTree.partial_tree(tree_one, 8)
  #   assert [partial: x] = MerkleTree.diff(partial, tree_two)

  #   assert partial2 = MerkleTree.partial_tree(tree_one, 8, x)
  #   assert [partial: y] = MerkleTree.diff(partial2, MerkleTree.partial_tree(tree_two, 8, x))

  #   assert partial3 = MerkleTree.partial_tree(tree_one, 8, <<x::bits, y::bits>>)

  #   assert [partial: z] =
  #            MerkleTree.diff(partial3, MerkleTree.partial_tree(tree_two, 8, <<x::bits, y::bits>>))

  #   assert partial4 = MerkleTree.partial_tree(tree_one, 8, <<x::bits, y::bits, z::bits>>)

  #   assert [partial: zz] =
  #            MerkleTree.diff(
  #              partial4,
  #              MerkleTree.partial_tree(tree_two, 8, <<x::bits, y::bits, z::bits>>)
  #            )

  #   assert partial5 =
  #            MerkleTree.partial_tree(tree_one, 8, <<x::bits, y::bits, z::bits, zz::bits>>)

  #   assert [:foo] =
  #            MerkleTree.diff(
  #              partial5,
  #              MerkleTree.partial_tree(tree_two, 8, <<x::bits, y::bits, z::bits, zz::bits>>)
  #            )

  #   # [partial, partial2, partial3, partial4, partial5]
  #   # |> Enum.map(&:erts_debug.size/1)
  #   # |> IO.inspect()
  # end
end
