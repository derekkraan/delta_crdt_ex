defmodule AWLWWMapTest do
  alias DeltaCrdt.{AWLWWMap, SemiLattice}
  use ExUnit.Case, async: true

  describe ".add/4" do
    test "can add an element" do
      map = AWLWWMap.new()

      assert %{one: 1} = SemiLattice.join(map, AWLWWMap.add(:one, 1, 1, map)) |> AWLWWMap.read()
    end

    test "can add a few elements" do
      map = AWLWWMap.new()

      crdt_map =
        [{:one, 1}, {:two, 4}, {:three, 9}]
        |> Enum.reduce(map, fn {key, val}, map ->
          SemiLattice.join(map, AWLWWMap.add(key, val, 1, map))
        end)
        |> AWLWWMap.read()

      assert %{one: 1, two: 4, three: 9} = crdt_map
    end
  end

  describe ".remove/3" do
    test "can remove an element" do
      map = AWLWWMap.new()

      crdt_map =
        [{:one, 1}, {:two, 4}, {:three, 9}]
        |> Enum.reduce(map, fn {key, val}, map ->
          SemiLattice.join(map, AWLWWMap.add(key, val, 1, map))
        end)

      with_removed_element = SemiLattice.join(crdt_map, AWLWWMap.remove(:two, 1, crdt_map))

      assert %{one: 1, three: 9} = AWLWWMap.read(with_removed_element)
      assert 2 = Enum.count(AWLWWMap.read(with_removed_element))
    end
  end

  describe ".clear/2" do
    test "removes all elements from the map" do
      map = AWLWWMap.new()

      crdt_map =
        [{:one, 1}, {:two, 4}, {:three, 9}]
        |> Enum.reduce(map, fn {key, val}, map ->
          SemiLattice.join(map, AWLWWMap.add(key, val, 1, map))
        end)

      cleared = SemiLattice.join(crdt_map, AWLWWMap.clear(1, crdt_map))

      assert Enum.empty?(AWLWWMap.read(cleared))
    end
  end
end
