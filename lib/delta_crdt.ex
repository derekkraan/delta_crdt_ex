defmodule DeltaCrdt do
  @moduledoc """
  Convenience functions to start and manage delta CRDTs provided by this library

  A CRDT is a conflict-free replicated data-type. That is to say, it is a distributed data structure that automatically resolves conflicts in a way that is consistent across all replicas of the data. In other words, your distributed data is guaranteed to eventually converge globally.

  Normal CRDTs (otherwise called "state CRDTs") require transmission of the entire CRDT state with every change. This clearly doesn't scale, but there has been exciting research in the last few years into "Delta CRDTs", CRDTs that only transmit their deltas. This has enabled a whole new scale of applications for CRDTs, and it's also what this library is based on.

  A Delta CRDT is made of two parts. First, the data structure itself, and second, an anti-entropy algorithm, which is responsible for convergence. `DeltaCrdt` implements Algorithm 2 from ["Delta State Replicated Data Types – Almeida et al. 2016"](https://arxiv.org/pdf/1603.01529.pdf) which is an anti-entropy algorithm for δ-CRDTs.

  While it is certainly interesting to have a look at this paper and spend time grokking it, in theory I've done the hard work so that you don't have to, and this library is the result.

  With this library, you can build distributed applications that share some state. `Horde.Supervisor` and `Horde.Registry` are both built atop `DeltaCrdt`, but there are certainly many more possibilities.

  Here's a simple example to illustrate the possibilities:

  ```
  iex> {:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 3)
  iex> {:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 3)
  iex> DeltaCrdt.add_neighbours(crdt1, [crdt2])
  iex> DeltaCrdt.read(crdt1)
  %{}
  iex> DeltaCrdt.mutate(crdt1, :add, ["CRDT", "is magic!"])
  iex> Process.sleep(10) # needed for the doctest
  iex> DeltaCrdt.read(crdt2)
  %{"CRDT" => "is magic!"}
  ```
  """

  @default_sync_interval 50
  @default_ship_interval 50
  @default_ship_debounce 50

  @type operation :: {function :: atom(), arguments :: list()}

  @doc """
  Start a DeltaCrdt and link it to the calling process.

  There are a number of options you can specify to tweak the behaviour of DeltaCrdt:
  - `notify: {pid, msg}` - when the state of the crdt has changed, `msg` will be sent to `pid`.
  - `sync_interval: 50` - the delta CRDT will attempt to sync its local changes with its neighbours at this interval. Default is 50.
  - `ship_interval: 50` - the delta CRDT will notify the listener at this interval, in ms. Default is 50.
  - `ship_debounce: 50` - debounce notify messages, in milliseconds. Default is 50.
  """
  @spec start_link(crdt_module :: module(), opts :: list(), genserver_opts :: list()) ::
          GenServer.on_start()
  def start_link(crdt_module, opts \\ [], genserver_opts \\ []) do
    GenServer.start_link(
      DeltaCrdt.CausalCrdt,
      {crdt_module, Keyword.get(opts, :notify, nil),
       Keyword.get(opts, :sync_interval, @default_sync_interval),
       Keyword.get(opts, :ship_interval, @default_ship_interval),
       Keyword.get(opts, :ship_debounce, @default_ship_debounce)},
      genserver_opts
    )
  end

  @doc """
  Include DeltaCrdt in a supervision tree with `{DeltaCrdt, [crdt: DeltaCrdt.AWLWWMap, name: MyCRDTMap]}`
  """
  def child_spec(opts \\ []) do
    name = Keyword.get(opts, :name, nil)
    crdt_module = Keyword.get(opts, :crdt, nil)
    shutdown = Keyword.get(opts, :shutdown, 5000)

    if is_nil(name) do
      raise "must specify :name in options, got: #{inspect(opts)}"
    end

    if is_nil(crdt_module) do
      raise "must specify :crdt in options, got: #{inspect(opts)}"
    end

    %{
      id: name,
      start:
        {DeltaCrdt.CausalCrdt, :start_link,
         [crdt_module, Keyword.drop(opts, [:name]), [name: name]]},
      shutdown: shutdown
    }
  end

  @doc """
  Notify the CRDT of its neighbours.

  This function will allow two CRDTs to communicate with each other and sync their states.

  Note: this sets up a unidirectional sync, so if you want bidirectional syncing (which is normally desirable), then you must call this function twice:
  ```
  DeltaCrdt.add_neighbours(c1, [c2])
  DeltaCrdt.add_neighbours(c2, [c1])
  ```
  """
  @spec add_neighbours(crdt :: GenServer.server(), neighbours :: list(GenServer.server())) :: :ok
  def add_neighbours(crdt, neighbours) when is_list(neighbours) do
    send(crdt, {:add_neighbours, neighbours})
    :ok
  end

  @spec mutate(crdt :: GenServer.server(), function :: atom, arguments :: list()) :: :ok
  @doc """
  Mutate the CRDT synchronously.

  For the asynchronous version of this function, see `mutate_async/3`.

  To see which operations are available, see the documentation for the crdt module that was provided in `start_link/3`.

  For example, AWLWWMap has a function `add` that takes 4 arguments. The last 2 arguments are supplied by DeltaCrdt internally, so you have to provide only the first two arguments: `key` and `val`. That would look like this: `DeltaCrdt.mutate(crdt, :add, ["CRDT", "is magic!"])`. This pattern is repeated for all mutation functions. Another exaple: to call `DeltaCrdt.AWLWWMap.clear`, use `DeltaCrdt.mutate(crdt, :clear, [])`.
  """
  def mutate(crdt, f, a)
      when is_atom(f) and is_list(a) do
    GenServer.call(crdt, {:operation, {f, a}})
  end

  @spec mutate_async(crdt :: GenServer.server(), function :: atom, arguments :: list()) :: :ok
  @doc """
  Mutate the CRDT asynchronously.
  """
  def mutate_async(crdt, f, a)
      when is_atom(f) and is_list(a) do
    GenServer.cast(crdt, {:operation, {f, a}})
  end

  @doc """
  Read the state of the CRDT.
  """
  @spec read(crdt :: GenServer.server(), timeout :: pos_integer()) :: crdt_state :: term()
  def read(crdt, timeout \\ 5000) do
    {crdt_module, state} = GenServer.call(crdt, :read, timeout)
    apply(crdt_module, :read, [state])
  end
end
