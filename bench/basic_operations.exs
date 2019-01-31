setup_crdt = fn number_of_items ->
  {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)
  {:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)
  {:ok, crdt3} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

  DeltaCrdt.add_neighbours(crdt1, [crdt2, crdt3])
  DeltaCrdt.add_neighbours(crdt2, [crdt1, crdt3])
  DeltaCrdt.add_neighbours(crdt3, [crdt2, crdt1])

  1..number_of_items |> Enum.each(fn x -> DeltaCrdt.mutate(crdt1, :add, [x, x]) end)

  crdt1
end

crdt_100 = setup_crdt.(100)
crdt_1000 = setup_crdt.(1000)
crdt_10_000 = setup_crdt.(10_000)

Benchee.run(%{
  "read (with 100 items)" => fn -> DeltaCrdt.read(crdt_100) end,
  "read (with 1.000 items)" => fn -> DeltaCrdt.read(crdt_1000) end,
  "read (with 10.000 items)" => fn -> DeltaCrdt.read(crdt_10_000) end,
  "add (with 100 items)" => fn -> DeltaCrdt.mutate(crdt_100, :add, ["key4", "value"]) end,
  "add (with 1.000 items)" => fn -> DeltaCrdt.mutate(crdt_1000, :add, ["key4", "value"]) end,
  "add (with 10.000 items)" => fn -> DeltaCrdt.mutate(crdt_10_000, :add, ["key4", "value"]) end,
  "remove (with 100 items)" => fn -> DeltaCrdt.mutate(crdt_100, :remove, [10]) end,
  "remove (with 1.000 items)" => fn -> DeltaCrdt.mutate(crdt_1000, :remove, [10]) end,
  "remove (with 10.000 items)" => fn -> DeltaCrdt.mutate(crdt_10_000, :remove, [10]) end
})
