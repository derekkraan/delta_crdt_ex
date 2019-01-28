defmodule BenchHelper do
  def get_result(fun, result) do
    case fun.() do
      ^result ->
        result

      other ->
        Process.sleep(500)
        get_result(fun, result)
    end
  end
end

add = fn total ->
  fn ->
    {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 1)
    {:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 1)
    DeltaCrdt.add_neighbours(crdt1, [crdt2])

    Enum.each(1..total, fn x ->
      DeltaCrdt.mutate(crdt1, :add, [x, x])
    end)

    BenchHelper.get_result(fn -> DeltaCrdt.read(crdt2) |> Map.get(total) end, total)
  end
end

Benchee.run(%{
  "add 10_000 records" => add.(10_000),
  "add 1_000 records" => add.(1000)
})
