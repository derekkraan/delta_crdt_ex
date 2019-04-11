do_test = fn number ->
  bench_pid = self()
  {:ok, c1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

  {:ok, c2} =
    DeltaCrdt.start_link(DeltaCrdt.AWLWWMap,
      on_diffs: fn diffs -> send(bench_pid, {:diffs, diffs}) end,
      subscribe_updates: {:diffs, bench_pid}
    )

  DeltaCrdt.set_neighbours(c1, [c2])
  DeltaCrdt.set_neighbours(c2, [c1])

  Enum.each(1..number, fn x ->
    DeltaCrdt.mutate(c1, :add, [x, x], 60_000)
  end)

  wait_loop = fn next_loop ->
    receive do
      {:diffs, diffs} ->
        # Enum.each(diffs, fn diff -> IO.inspect(diff) end)

        Enum.any?(diffs, fn
          {:add, ^number, ^number} -> true
          {:remove, ^number} -> true
          _ -> false
        end)
        |> if do
          nil
        else
          next_loop.(next_loop)
        end
    after
      60_000 -> raise "timed out"
    end
  end

  wait_loop.(wait_loop)

  Enum.each(1..number, fn x ->
    DeltaCrdt.mutate(c1, :remove, [x], 60_000)
  end)

  wait_loop.(wait_loop)

  Process.exit(c1, :normal)
  Process.exit(c2, :normal)
end

Benchee.run(%{"add and remove" => do_test},
  # inputs: %{10 => 10, 100 => 100, 500 => 500, 1000 => 1000, 5000 => 5000, 10_000 => 10_000}
  inputs: %{
    10 => 10,
    100 => 100,
    1000 => 1000,
    10_000 => 10_000,
    20_000 => 20_000,
    30_000 => 30_000
  }
  # formatters: [Benchee.Formatters.HTML, Benchee.Formatters.Console]
)
