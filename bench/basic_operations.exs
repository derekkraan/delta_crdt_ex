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

Benchee.run(
  %{
    # "read" => fn crdt -> DeltaCrdt.read(crdt) end,
    "add" => fn crdt -> DeltaCrdt.mutate(crdt, :add, ["key4", "value"]) end,
    "update" => fn crdt -> DeltaCrdt.mutate(crdt, :add, [10, 12]) end,
    "remove" => fn crdt -> DeltaCrdt.mutate(crdt, :remove, [10]) end
  },
  inputs: %{
    # "with 100" => setup_crdt.(100),
    "with 1000" => setup_crdt.(1000)
    # "with 10_000" => setup_crdt.(10_000)
  },
  before_scenario: fn crdt ->
    DeltaCrdt.mutate(crdt, :add, [10, 10])
    crdt
  end,
  after_scenario: fn crdt ->
    DeltaCrdt.mutate(crdt, :remove, ["key4"])
  end
)
