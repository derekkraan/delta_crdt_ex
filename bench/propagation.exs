defmodule UpdateListener do
  use GenServer

  def wait_for_update(pid) do
    GenServer.call(pid, :wait_for_update)
  end

  def init(args) do
    {:ok, {nil, nil}}
  end

  def handle_call(:wait_for_update, from, {nil, nil}) do
    {:noreply, {from, nil}}
  end

  def handle_call(:wait_for_update, from, {nil, response}) do
    {:reply, :ok, {nil, nil}}
  end

  def handle_info({:crdt_update, _msg}, {nil, nil}) do
    {:noreply, {nil, :updated}}
  end

  def handle_info({:crdt_update, _msg}, {from, nil}) do
    GenServer.reply(from, :ok)
    {:noreply, {nil, nil}}
  end
end

defmodule Counter do
  use Agent

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def next do
    Agent.update(__MODULE__, &(&1 + 1))
    Agent.get(__MODULE__, & &1)
  end
end

{:ok, listener} = GenServer.start_link(UpdateListener, [])

{:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)
{:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, notify: {listener, :crdt_update})

DeltaCrdt.add_neighbours(crdt1, [crdt2])
DeltaCrdt.add_neighbours(crdt2, [crdt1])

Counter.start_link(0)

Benchee.run(%{
  "Add something" => fn ->
    index = Counter.next()
    IO.puts(index)
    DeltaCrdt.mutate(crdt1, :add, [index, index])
    UpdateListener.wait_for_update(listener) |> IO.inspect()
  end
})
