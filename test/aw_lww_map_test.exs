defmodule AWLWWMapTest do
  alias DeltaCrdt.{AWLWWMap, SemiLattice}
  use ExUnit.Case, async: true
  use ExUnitProperties

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

    property "arbitrary add and remove sequence results in correct map" do
      operation =
        ExUnitProperties.gen all op <- StreamData.member_of([:add, :remove]),
                                 key <- term(),
                                 value <- term() do
          {op, key, value}
        end

      check all operations <- list_of(operation) do
        actual_result =
          operations
          |> Enum.reduce(AWLWWMap.new(), fn
            {:add, key, val}, crdt ->
              SemiLattice.join(crdt, AWLWWMap.add(key, val, 1, crdt))

            {:remove, key, val}, crdt ->
              SemiLattice.join(crdt, AWLWWMap.remove(key, 1, crdt))
          end)
          |> AWLWWMap.read()

        correct_result =
          operations
          |> Enum.reduce(%{}, fn
            {:add, key, value}, map ->
              Map.put(map, key, value)

            {:remove, key, value}, map ->
              Map.delete(map, key)
          end)

        assert actual_result == correct_result
      end
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
