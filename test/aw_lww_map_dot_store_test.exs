defmodule DeltaCrdt.AWLWWMap.DotStoreTest do
  use ExUnit.Case, async: true

  alias DeltaCrdt.AWLWWMap.DotStore

  test "can compress dots" do
    compressed = DotStore.compress([{1, 1}, {1, 2}])
    assert %{1 => 2} = compressed
    assert 1 = map_size(compressed)

    assert %{1 => 2, 2 => 3} = DotStore.compress([{1, 2}, {1, 1}, {2, 2}, {2, 3}])
  end

  test "compression is idempotent" do
    compressed =
      DotStore.compress([{1, 1}, {1, 2}])
      |> DotStore.compress()

    assert %{1 => 2} = compressed
    assert 1 = map_size(compressed)
  end

  test "can union dots" do
    dots1 = MapSet.new([{1, 1}])
    dots2 = MapSet.new([{1, 1}, {1, 2}])
    assert MapSet.new([{1, 1}, {1, 2}]) == DotStore.union(dots1, dots2)
  end

  test "can union compressed dots" do
    dots1 = MapSet.new([{1, 1}])
    dots2 = MapSet.new([{1, 1}, {1, 2}]) |> DotStore.compress()
    assert %{1 => 2} == DotStore.union(dots1, dots2)
  end

  test "can test if a dot is a member" do
    dots1 = MapSet.new([{1, 1}, {2, 1}, {2, 2}])
    assert DotStore.member?(dots1, {1, 1})
    assert DotStore.member?(dots1, {2, 1})
    assert DotStore.member?(dots1, {2, 2})
    refute DotStore.member?(dots1, {3, 1})
    refute DotStore.member?(dots1, {1, 2})
    refute DotStore.member?(dots1, {2, 3})

    compressed_dots = DotStore.compress(dots1)
    assert DotStore.member?(compressed_dots, {1, 1})
    assert DotStore.member?(compressed_dots, {2, 1})
    assert DotStore.member?(compressed_dots, {2, 2})
    refute DotStore.member?(compressed_dots, {3, 1})
    refute DotStore.member?(compressed_dots, {1, 2})
    refute DotStore.member?(compressed_dots, {2, 3})
  end

  test "can calculate intersection" do
    dots1 = MapSet.new([{1, 1}])
    dots2 = MapSet.new([{1, 2}])
    assert MapSet.new([]) == DotStore.intersection(dots1, dots2)

    assert MapSet.new([{1, 1}]) == DotStore.intersection(dots1, dots1)
  end

  test "can calculate intersection on compressed dots" do
    dots1 = MapSet.new([{1, 1}, {1, 2}, {2, 1}])
    dots2 = MapSet.new([{1, 1}, {1, 2}, {2, 2}]) |> DotStore.compress()
    assert MapSet.new([{1, 1}, {1, 2}, {2, 1}]) == DotStore.intersection(dots1, dots2)

    dots1 = MapSet.new([{1, 1}, {1, 2}, {2, 1}]) |> DotStore.compress()
    dots2 = MapSet.new([{1, 1}, {1, 2}, {2, 2}]) |> DotStore.compress()

    assert MapSet.new([{1, 1}, {1, 2}, {2, 1}]) ==
             DotStore.intersection(dots1, dots2) |> DotStore.decompress()
  end

  test "can calculate max_dots" do
    dots = MapSet.new([{1, 1}, {1, 2}])
    assert %{1 => 2} == DotStore.max_dots(dots)
    assert %{1 => 2} == DotStore.compress(dots) |> DotStore.max_dots()
  end

  test "can calculate min_dots" do
    dots = MapSet.new([{1, 1}, {1, 2}])
    assert %{1 => 1} == DotStore.min_dots(dots)
    assert %{1 => 1} == DotStore.compress(dots) |> DotStore.min_dots()
  end
end
