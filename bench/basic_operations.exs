setup_crdt = fn number_of_items ->
  {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

  1..number_of_items |> Enum.each(fn x -> DeltaCrdt.mutate(crdt1, :add, [x, x]) end)

  crdt1
end

trace = fn ->
  crdt = setup_crdt.(1000)

  # TRACING:
  :fprof.trace(:start, procs: [crdt])
  # # add_and_remove.(1000).()
  Enum.each(1..1000, fn x ->
    DeltaCrdt.mutate(crdt, :add, ["key#{x}", "value"])
  end)

  :fprof.trace(:stop)
  #
  :fprof.profile()
  :fprof.analyse(dest: 'perf', cols: 120)
end

bench = fn ->
  Benchee.run(
    %{
      "read" => fn crdt -> DeltaCrdt.read(crdt) end,
      "add" => fn crdt -> DeltaCrdt.mutate(crdt, :add, ["key4", "value"]) end,
      "update" => fn crdt -> DeltaCrdt.mutate(crdt, :add, [10, 12]) end,
      "remove" => fn crdt -> DeltaCrdt.mutate(crdt, :remove, [10]) end
    },
    inputs: %{
      "with 1000" => setup_crdt.(1000)
      # "with 10_000" => setup_crdt.(10_000)
    },
    before_each: fn crdt ->
      DeltaCrdt.mutate(crdt, :add, [10, 10])
      DeltaCrdt.mutate(crdt, :remove, ["key4"])
      crdt
    end
  )
end

bench.()
