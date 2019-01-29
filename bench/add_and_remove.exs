defmodule BenchHelper do
  def get_result(fun, result) do
    case fun.() do
      ^result ->
        result

      _other ->
        Process.sleep(50)
        get_result(fun, result)
    end
  end
end

add = fn total ->
  fn ->
    {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 50)
    {:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 50)
    DeltaCrdt.add_neighbours(crdt1, [crdt2])

    Enum.each(1..total, fn x ->
      DeltaCrdt.mutate(crdt1, :add, [x, x])
    end)

    BenchHelper.get_result(
      fn ->
        DeltaCrdt.read(crdt2) |> Map.get(total)
      end,
      total
    )
  end
end

# :fprof.trace(:start)

Benchee.run(%{
  # "add 500 records" => add.(500)
  "add 1_000 records" => add.(1_000),
  "add 5_000 records" => add.(5000)
})

# :fprof.trace(:stop)

# :fprof.profile()
# :fprof.analyse(dest: 'fprof.analyse', cols: 120)
