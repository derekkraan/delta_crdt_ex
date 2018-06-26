alias DeltaCrdt.{AWLWWMap, SemiLattice}
map = AWLWWMap.new()

with_100 =
  1..100
  |> Enum.reduce(map, fn x, map ->
    SemiLattice.join(map, AWLWWMap.add(x, x, 1, map))
  end)
  |> SemiLattice.compress()

with_1000 =
  1..1000
  |> Enum.reduce(map, fn x, map ->
    SemiLattice.join(map, AWLWWMap.add(x, x, 1, map))
  end)
  |> SemiLattice.compress()

with_10000 =
  1..10000
  |> Enum.reduce(map, fn x, map ->
    SemiLattice.join(map, AWLWWMap.add(x, x, 1, map))
  end)
  |> SemiLattice.compress()

with_100000 =
  1..100_000
  |> Enum.reduce(map, fn x, map ->
    join = SemiLattice.join(map, AWLWWMap.add(x, x, 1, map))

    if 0 == rem(x, 5000) do
      SemiLattice.compress(join)
    else
      join
    end
  end)
  |> SemiLattice.compress()

normal_map_100000 =
  1..100_000
  |> Enum.reduce(map, fn x, map ->
    Map.put(map, x, 1)
  end)

Benchee.run(
  %{
    "Elixir map L" => fn ->
      Map.put(normal_map_100000, 91_919_191, 9_191_919_191)
    end,
    "XS (100)" => fn ->
      SemiLattice.join(with_100, AWLWWMap.add(91_919_191, 9_191_919_191, 1, with_100))
    end,
    "S (1000)" => fn ->
      SemiLattice.join(with_1000, AWLWWMap.add(91_919_191, 9_191_919_191, 1, with_1000))
    end,
    "M (10000)" => fn ->
      SemiLattice.join(with_10000, AWLWWMap.add(91_919_191, 9_191_919_191, 1, with_10000))
    end,
    "L (100000)" => fn ->
      SemiLattice.join(with_100000, AWLWWMap.add(91_919_191, 9_191_919_191, 1, with_100000))
    end
  },
  print: [fast_warning: false]
)
