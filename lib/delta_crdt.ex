defmodule DeltaCrdt do
  @moduledoc """
  Start and interact with the Delta CRDTs provided by this library.

  A CRDT is a conflict-free replicated data-type. That is to say, it is a distributed data structure that automatically resolves conflicts in a way that is consistent across all replicas of the data. In other words, your distributed data is guaranteed to eventually converge globally.

  Normal CRDTs (otherwise called "state CRDTs") require transmission of the entire CRDT state with every change. This clearly doesn't scale, but there has been exciting research in the last few years into "Delta CRDTs", CRDTs that only transmit their deltas. This has enabled a whole new scale of applications for CRDTs, and it's also what this library is based on.

  A Delta CRDT is made of two parts. First, the data structure itself, and second, an anti-entropy algorithm, which is responsible for ensuring convergence. `DeltaCrdt` implements Algorithm 2 from ["Delta State Replicated Data Types – Almeida et al. 2016"](https://arxiv.org/pdf/1603.01529.pdf) which is an anti-entropy algorithm for δ-CRDTs. `DeltaCrdt` also implements join decomposition to ensure that deltas aren't transmitted unnecessarily in the cluster.

  While it is certainly interesting to have a look at this paper and spend time grokking it, in theory I've done the hard work so that you don't have to, and this library is the result.

  With this library, you can build distributed applications that share some state. [`Horde.Supervisor`](https://hexdocs.pm/horde/Horde.Supervisor.html) and [`Horde.Registry`](https://hexdocs.pm/horde/Horde.Registry.html) are both built atop `DeltaCrdt`, but there are certainly many more possibilities.

  Here's a simple example for illustration:

  ```
  iex> {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 3)
  iex> {:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 3)
  iex> DeltaCrdt.set_neighbours(crdt1, [crdt2])
  iex> DeltaCrdt.set_neighbours(crdt2, [crdt1])
  iex> DeltaCrdt.to_map(crdt1)
  %{}
  iex> DeltaCrdt.put(crdt1, "CRDT", "is magic!")
  iex> Process.sleep(10) # need to wait for propagation for the doctest
  iex> DeltaCrdt.to_map(crdt2)
  %{"CRDT" => "is magic!"}
  ```
  """

  @default_sync_interval 200
  @default_max_sync_size 200
  @default_timeout 5_000

  @type t :: GenServer.server()
  @type key :: any()
  @type value :: any()
  @type diff :: {:add, key :: any(), value :: any()} | {:remove, key :: any()}
  @type crdt_option ::
          {:on_diffs, ([diff()] -> any()) | {module(), function(), [any()]}}
          | {:sync_interval, pos_integer()}
          | {:max_sync_size, pos_integer() | :infinite}
          | {:storage_module, DeltaCrdt.Storage.t()}

  @type crdt_options :: [crdt_option()]

  @doc """
  Start a DeltaCrdt and link it to the calling process.

  There are a number of options you can specify to tweak the behaviour of DeltaCrdt:
  - `:sync_interval` - the delta CRDT will attempt to sync its local changes with its neighbours at this interval (specified in milliseconds). Default is 200.
  - `:on_diffs` - function which will be invoked on every diff
  - `:max_sync_size` - maximum size of synchronization (specified in number of items to sync)
  - `:storage_module` - module which implements `DeltaCrdt.Storage` behaviour
  """
  @spec start_link(
          crdt_module :: module(),
          opts :: crdt_options()
        ) :: GenServer.on_start()
  def start_link(crdt_module, opts \\ []) do
    init_arg =
      Keyword.put(opts, :crdt_module, crdt_module)
      |> Keyword.put_new(:sync_interval, @default_sync_interval)
      |> Keyword.put_new(:max_sync_size, @default_max_sync_size)

    GenServer.start_link(DeltaCrdt.CausalCrdt, init_arg, Keyword.take(opts, [:name]))
  end

  @doc """
  Include DeltaCrdt in a supervision tree with `{DeltaCrdt, [crdt: DeltaCrdt.AWLWWMap, name: MyCRDTMap]}`
  """
  def child_spec(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    crdt_module = Keyword.get(opts, :crdt, nil)
    shutdown = Keyword.get(opts, :shutdown, 5000)

    if is_nil(crdt_module) do
      raise "must specify :crdt in options, got: #{inspect(opts)}"
    end

    %{
      id: name,
      start: {DeltaCrdt, :start_link, [crdt_module, opts]},
      shutdown: shutdown
    }
  end

  @doc """
  Notify a CRDT of its neighbours.

  This function allows CRDTs to communicate with each other and sync their states.

  **Note: this sets up a unidirectional sync, so if you want bidirectional syncing (which is normally desirable), then you must call this function twice (or thrice for 3 nodes, etc):**
  ```
  DeltaCrdt.set_neighbours(c1, [c2, c3])
  DeltaCrdt.set_neighbours(c2, [c1, c3])
  DeltaCrdt.set_neighbours(c3, [c1, c2])
  ```
  """
  @spec set_neighbours(crdt :: t(), neighbours :: list(t())) :: :ok
  def set_neighbours(crdt, neighbours) when is_list(neighbours) do
    send(crdt, {:set_neighbours, neighbours})
    :ok
  end

  @spec put(t(), key(), value(), timeout()) :: t()
  def put(crdt, key, value, timeout \\ @default_timeout) do
    :ok = GenServer.call(crdt, {:operation, {:add, [key, value]}}, timeout)
    crdt
  end

  @spec merge(t(), map(), timeout()) :: t()
  def merge(crdt, map, timeout \\ @default_timeout) do
    :ok =
      GenServer.call(
        crdt,
        {:bulk_operation, Enum.map(map, fn {key, value} -> {:add, [key, value]} end)},
        timeout
      )

    crdt
  end

  @spec drop(t(), [key()], timeout()) :: t()
  def drop(crdt, keys, timeout \\ @default_timeout) do
    :ok =
      GenServer.call(
        crdt,
        {:bulk_operation, Enum.map(keys, fn key -> {:remove, [key]} end)},
        timeout
      )

    crdt
  end

  @spec delete(t(), key(), timeout()) :: t()
  def delete(crdt, key, timeout \\ @default_timeout) do
    :ok = GenServer.call(crdt, {:operation, {:remove, [key]}}, timeout)
    crdt
  end

  @spec get(t(), key(), timeout()) :: value()
  def get(crdt, key, timeout \\ @default_timeout) do
    case GenServer.call(crdt, {:read, [key]}, timeout) do
      %{^key => elem} -> elem
      _ -> nil
    end
  end

  @spec take(t(), [key()], timeout()) :: [{key(), value()}]
  def take(crdt, keys, timeout \\ @default_timeout) when is_list(keys) do
    GenServer.call(crdt, {:read, keys}, timeout)
  end

  @spec to_map(t(), timeout()) :: map()
  def to_map(crdt, timeout \\ @default_timeout) do
    GenServer.call(crdt, :read, timeout)
  end

  @spec mutate(
          crdt :: t(),
          function :: atom,
          arguments :: list(),
          timeout :: timeout()
        ) :: :ok
  @doc """
  Mutate the CRDT synchronously.

  For the asynchronous version of this function, see `mutate_async/3`.

  To see which operations are available, see the documentation for the crdt module that was provided in `start_link/3`.

  For example, `DeltaCrdt.AWLWWMap` has a function `add` that takes 4 arguments. The last 2 arguments are supplied by DeltaCrdt internally, so you have to provide only the first two arguments: `key` and `val`. That would look like this: `DeltaCrdt.mutate(crdt, :add, ["CRDT", "is magic!"])`. This pattern is repeated for all mutation functions. Another example: to call `DeltaCrdt.AWLWWMap.clear`, use `DeltaCrdt.mutate(crdt, :clear, [])`.
  """
  @deprecated "Use put/4 instead"
  def mutate(crdt, f, a, timeout \\ @default_timeout)
      when is_atom(f) and is_list(a) do
    GenServer.call(crdt, {:operation, {f, a}}, timeout)
  end

  @spec mutate_async(crdt :: t(), function :: atom, arguments :: list()) :: :ok
  @doc """
  Mutate the CRDT asynchronously.
  """
  @deprecated "Will be removed without replacement in a future version"
  def mutate_async(crdt, f, a)
      when is_atom(f) and is_list(a) do
    GenServer.cast(crdt, {:operation, {f, a}})
  end

  @doc """
  Read the state of the CRDT.

  Forwards arguments to the used crdt module, so `read(crdt, ["my-key"])` would call `crdt_module.read(state, ["my-key"])`.

  For example, `DeltaCrdt.AWLWWMap` accepts a list of keys to limit the returned values instead of returning everything.
  """
  @spec read(crdt :: t()) :: crdt_state :: term()
  @spec read(crdt :: t(), timeout :: timeout()) :: crdt_state :: term()
  @spec read(crdt :: t(), keys :: list()) :: crdt_state :: term()
  @spec read(crdt :: t(), keys :: list(), timeout :: timeout()) ::
          crdt_state :: term()
  @deprecated "Use get/2 or take/3 or to_map/2"
  def read(crdt), do: read(crdt, @default_timeout)
  def read(crdt, keys) when is_list(keys), do: read(crdt, keys, @default_timeout)

  def read(crdt, timeout) do
    GenServer.call(crdt, :read, timeout)
  end

  def read(crdt, keys, timeout) when is_list(keys) do
    GenServer.call(crdt, {:read, keys}, timeout)
  end
end
