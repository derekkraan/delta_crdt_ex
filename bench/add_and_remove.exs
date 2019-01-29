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

add_and_remove = fn total ->
  fn ->
    {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 50)
    {:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 50)
    DeltaCrdt.add_neighbours(crdt1, [crdt2])

    Enum.each(1..(total - 1), fn x ->
      DeltaCrdt.mutate(crdt1, :add, [x, x])
    end)

    Enum.each(1..(total - 1), fn x ->
      DeltaCrdt.mutate(crdt1, :remove, [x])
    end)

    DeltaCrdt.mutate(crdt1, :add, [total, total])

    BenchHelper.get_result(
      fn ->
        DeltaCrdt.read(crdt2, :infinity) |> Map.get(total)
      end,
      total
    )
  end
end

Benchee.run(%{
  "add and remove 1_000 records" => add_and_remove.(1_000),
  "add and remove 5_000 records" => add_and_remove.(5_000)
})

# TRACING:
# :fprof.trace(:start)
# add_and_remove.(1000).()
# :fprof.trace(:stop)

# :fprof.profile()
# :fprof.analyse(dest: 'fprof.analyse', cols: 120)
