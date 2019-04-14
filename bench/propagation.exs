defmodule BenchRecorder do
  use GenServer

  def subscribe_to(msg) do
    GenServer.call(__MODULE__, {:set_pid_msg, self(), msg})
  end

  def start_link() do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil), do: {:ok, {nil, nil}}

  def handle_info({:diffs, _diffs}, {nil, nil}) do
    {:noreply, {nil, nil}}
  end

  def handle_info({:diffs, diffs}, {pid, msg}) do
    if Enum.member?(diffs, msg) do
      send(pid, msg)
      {:noreply, {nil, nil}}
    else
      {:noreply, {pid, msg}}
    end
  end

  def handle_call({:set_pid_msg, pid, msg}, _from, _) do
    {:reply, :ok, {pid, msg}}
  end
end

BenchRecorder.start_link()

prepare = fn number ->
  BenchRecorder.subscribe_to({:add, number, number})

  {:ok, c1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 5)

  {:ok, c2} =
    DeltaCrdt.start_link(DeltaCrdt.AWLWWMap,
      on_diffs: fn diffs -> send(BenchRecorder, {:diffs, diffs}) end
    )

  DeltaCrdt.set_neighbours(c1, [c2])
  DeltaCrdt.set_neighbours(c2, [c1])

  Enum.each(1..number, fn x ->
    DeltaCrdt.mutate(c1, :add, [x, x], 60_000)
  end)

  receive do
    {:add, ^number, ^number} -> :ok
  after
    60_000 -> raise "waited for 60s"
  end

  :ok = GenServer.call(c1, :hibernate, 15_000)
  :ok = GenServer.call(c2, :hibernate, 15_000)
  :ok = GenServer.call(c1, :ping, 15_000)
  :ok = GenServer.call(c2, :ping, 15_000)

  {c1, c2}
end

perform = fn {c1, c2}, op ->
  range =
    case op do
      :add ->
        100_000..100_010

      :remove ->
        1..10
    end

  Enum.each(range, fn x ->
    case op do
      :add ->
        BenchRecorder.subscribe_to({:add, 100_010, 100_010})
        DeltaCrdt.mutate(c1, :add, [x, x], 60_000)

      :remove ->
        BenchRecorder.subscribe_to({:remove, 10})
        DeltaCrdt.mutate(c1, :remove, [x], 60_000)
    end
  end)

  case op do
    :add ->
      receive do
        {:add, 100_010, 100_010} -> :ok
      after
        60_000 -> raise "waited for 60s"
      end

    :remove ->
      receive do
        {:remove, 10} -> :ok
      after
        60_000 -> raise "waited for 60s"
      end
  end

  Process.exit(c1, :normal)
  Process.exit(c2, :normal)
end

Benchee.run(
  %{
    "add 10" => fn input -> perform.(input, :add) end,
    "remove 10" => fn input -> perform.(input, :remove) end
  },
  before_each: fn input -> prepare.(input) end,
  inputs: %{
    # 10 => 10,
    # 100 => 100,
    # 1000 => 1000,
    # 10_000 => 10_000,
    20_000 => 20_000,
    30_000 => 30_000
  }
  # formatters: [Benchee.Formatters.HTML, Benchee.Formatters.Console]
)
