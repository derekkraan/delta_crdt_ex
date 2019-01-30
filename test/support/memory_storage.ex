defmodule MemoryStorage do
  @behaviour DeltaCrdt.Storage
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def write(name, state) do
    GenServer.call(__MODULE__, {:write, name, state})
  end

  def read(name) do
    GenServer.call(__MODULE__, {:read, name})
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call({:write, name, state}, _from, map) do
    {:reply, :ok, Map.put(map, name, state)}
  end

  def handle_call({:read, name}, _from, map) do
    {:reply, Map.get(map, name), map}
  end
end
