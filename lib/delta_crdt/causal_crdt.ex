defmodule DeltaCrdt.CausalCrdt do
  use GenServer

  require Logger

  @default_ship_interval 50
  @default_ship_debounce 50

  @outstanding_ack_timeout 20_000

  @ship_after_x_deltas 100
  @gc_interval 10_000

  @type delta :: {k :: integer(), delta :: any()}
  @type delta_interval :: {a :: integer(), b :: integer(), delta :: delta()}

  @moduledoc """
  DeltaCrdt implements Algorithm 2 from `Delta State Replicated Data Types – Almeida et al. 2016`
  which is an anti-entropy algorithm for δ-CRDTs. You can find the original paper here: https://arxiv.org/pdf/1603.01529.pdf
  """

  defmodule State do
    defstruct node_id: nil,
              notify: nil,
              neighbours: MapSet.new(),
              crdt_module: nil,
              crdt_state: nil,
              shipped_sequence_number: 0,
              sequence_number: 0,
              ship_debounce: 0,
              deltas: %{},
              ack_map: %{},
              outstanding_acks: %{}
  end

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
      start: {__MODULE__, :start_link, [crdt_module, Keyword.drop(opts, [:name]), [name: name]]},
      shutdown: shutdown
    }
  end

  @doc """
  Start a DeltaCrdt.
  """
  def start_link(crdt_module, opts \\ [], genserver_opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      {crdt_module, Keyword.get(opts, :notify, nil),
       Keyword.get(opts, :ship_interval, @default_ship_interval),
       Keyword.get(opts, :ship_debounce, @default_ship_debounce)},
      genserver_opts
    )
  end

  def read(server, timeout \\ 5000) do
    {crdt_module, state} = GenServer.call(server, :read, timeout)
    apply(crdt_module, :read, [state])
  end

  ### GenServer callbacks

  def init({crdt_module, notify, ship_interval, ship_debounce}) do
    DeltaCrdt.Periodic.start_link(:garbage_collect_deltas, @gc_interval)
    DeltaCrdt.Periodic.start_link(:ship, ship_interval)
    DeltaCrdt.Periodic.start_link(:try_ship_client, ship_interval)

    Process.flag(:trap_exit, true)

    {:ok,
     %State{
       node_id: :rand.uniform(1_000_000_000),
       notify: notify,
       crdt_module: crdt_module,
       ship_debounce: ship_debounce,
       crdt_state: crdt_module.new()
     }}
  end

  def terminate(_reason, state) do
    ship_interval_or_state_to_all(state)
  end

  @spec ship_state_to_neighbour(term(), term()) :: neighbour :: term() | nil
  defp ship_state_to_neighbour(neighbour, state) do
    remote_acked = Map.get(state.ack_map, neighbour, 0)

    if Enum.empty?(state.deltas) || Enum.min(Map.keys(state.deltas)) > remote_acked do
      send(neighbour, {:delta, {self(), neighbour, state.crdt_state}, state.sequence_number})
      {neighbour, state.sequence_number}
    else
      state.deltas
      |> Enum.filter(fn
        {_i, {^neighbour, _delta}} -> false
        _ -> true
      end)
      |> Enum.filter(fn {i, _delta} -> remote_acked <= i && i < state.sequence_number end)
      |> case do
        [] ->
          nil

        deltas ->
          delta_interval =
            Enum.map(deltas, fn {_i, {_from, delta}} -> delta end)
            |> Enum.reduce(fn delta, delta_interval ->
              DeltaCrdt.SemiLattice.join(delta_interval, delta)
            end)

          if(remote_acked < state.sequence_number) do
            send(neighbour, {:delta, {self(), neighbour, delta_interval}, state.sequence_number})
            {neighbour, state.sequence_number}
          end
      end
    end
  end

  defp ship_interval_or_state_to_all(state) do
    shipped_to =
      MapSet.difference(state.neighbours, MapSet.new(Map.keys(state.outstanding_acks)))
      |> Enum.map(fn n -> ship_state_to_neighbour(n, state) end)
      |> Enum.filter(fn
        nil -> false
        {neighbour, sequence_number} -> {neighbour, sequence_number}
      end)
      |> Map.new()

    set_outstanding_ack_timeout(shipped_to)

    Map.merge(state.outstanding_acks, shipped_to)
  end

  defp set_outstanding_ack_timeout(outstanding_acks) do
    Enum.each(outstanding_acks, fn {neighbour, sequence_number} ->
      Process.send_after(
        self(),
        {:cancel_outstanding_ack, neighbour, sequence_number},
        @outstanding_ack_timeout
      )
    end)
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:add_neighbours, pids}, state) do
    new_neighbours = pids |> MapSet.new() |> MapSet.union(state.neighbours)
    {:noreply, %{state | neighbours: new_neighbours}}
  end

  def handle_info(
        {:delta,
         {neighbour, self_reference, %{state: _d_s, causal_context: delta_c} = delta_interval},
         n},
        %{crdt_state: %{state: _s, causal_context: c}} = state
      ) do
    if DeltaCrdt.AntiEntropy.is_strict_expansion(c, delta_c) do
      send(neighbour, {:ack, self_reference, n})

      new_state =
        case DeltaCrdt.SemiLattice.minimum_delta(state.crdt_state, delta_interval) do
          {_new_crdt_state, :bottom} ->
            state

          {new_crdt_state, minimum_delta} ->
            new_deltas = Map.put(state.deltas, state.sequence_number, {neighbour, minimum_delta})
            new_sequence_number = state.sequence_number + 1

            %{
              state
              | crdt_state: new_crdt_state,
                deltas: new_deltas,
                sequence_number: new_sequence_number
            }
        end

      {:noreply, new_state}
    else
      Logger.debug(fn ->
        "not applying delta interval from #{inspect(neighbour)} because delta interval is not a strict expansion"
      end)

      {:noreply, state}
    end
  end

  def handle_info({:ack, neighbour, n}, state) do
    if(Map.get(state.ack_map, neighbour, 0) > n) do
      {:noreply, state}
    else
      new_ack_map = Map.put(state.ack_map, neighbour, n)
      new_outstanding_acks = Map.delete(state.outstanding_acks, neighbour)
      {:noreply, %{state | ack_map: new_ack_map, outstanding_acks: new_outstanding_acks}}
    end
  end

  def handle_info({:ship_client, reply_to, s}, %{sequence_number: s} = state) do
    send_notification(state, reply_to)
    {:noreply, %{state | shipped_sequence_number: s}}
  end

  def handle_info(
        {:ship_client, reply_to, _s},
        %{sequence_number: seq, shipped_sequence_number: shipped} = state
      )
      when seq - shipped > @ship_after_x_deltas do
    send_notification(state, reply_to)
    {:noreply, %{state | shipped_sequence_number: seq}}
  end

  def handle_info({:ship_client, reply_to, _s}, state) do
    Process.send_after(
      self(),
      {:ship_client, reply_to, state.sequence_number},
      state.ship_debounce
    )

    {:noreply, state}
  end

  def handle_info({:cancel_outstanding_ack, neighbour, sequence_number}, state) do
    new_outstanding_acks =
      case Map.get(state.outstanding_acks, neighbour) do
        ^sequence_number -> Map.delete(state.outstanding_acks, neighbour)
        _ -> state.outstanding_acks
      end

    {:noreply, %{state | outstanding_acks: new_outstanding_acks}}
  end

  def handle_call(:garbage_collect_deltas, _from, state) do
    compressed_crdt_state = DeltaCrdt.SemiLattice.compress(state.crdt_state)

    if Enum.empty?(state.neighbours) do
      {:noreply, %{state | crdt_state: compressed_crdt_state}}
    else
      l =
        state.neighbours
        |> Enum.filter(fn neighbour -> Map.has_key?(state.ack_map, neighbour) end)
        |> Enum.map(fn neighbour -> Map.get(state.ack_map, neighbour, 0) end)
        |> Enum.min(fn -> 0 end)

      new_deltas = state.deltas |> Enum.filter(fn {i, _delta} -> i >= l end) |> Map.new()
      {:reply, :ok, %{state | deltas: new_deltas, crdt_state: compressed_crdt_state}}
    end
  end

  def handle_call(
        :try_ship_client,
        _f,
        %{shipped_sequence_number: same, sequence_number: same} = state
      ) do
    {:reply, :ok, state}
  end

  def handle_call(:try_ship_client, from, state) do
    Process.send_after(self(), {:ship_client, from, state.sequence_number}, state.ship_debounce)
    {:noreply, state}
  end

  def handle_call(:ship, _from, state) do
    outstanding_acks = ship_interval_or_state_to_all(state)
    {:reply, :ok, %{state | outstanding_acks: outstanding_acks}}
  end

  def handle_call(:read, _from, %{crdt_module: crdt_module, crdt_state: crdt_state} = state),
    do: {:reply, {crdt_module, crdt_state}, state}

  def handle_call({:read, module}, _from, state) do
    ret = apply(module, :read, [state.crdt_state])
    {:reply, ret, state}
  end

  def handle_call({:operation, operation}, _from, state) do
    {:reply, :ok, handle_operation(operation, state)}
  end

  def handle_cast({:operation, operation}, state) do
    {:noreply, handle_operation(operation, state)}
  end

  defp handle_operation({function, args}, state) do
    delta = apply(state.crdt_module, function, args ++ [state.node_id, state.crdt_state])

    case DeltaCrdt.SemiLattice.minimum_delta(state.crdt_state, delta) do
      {_new_crdt_state, :bottom} ->
        state

      {new_crdt_state, minimum_delta} ->
        new_deltas = Map.put(state.deltas, state.sequence_number, {self(), minimum_delta})

        new_sequence_number = state.sequence_number + 1

        Map.put(state, :deltas, new_deltas)
        |> Map.put(:crdt_state, new_crdt_state)
        |> Map.put(:sequence_number, new_sequence_number)
    end
  end

  defp send_notification(%{notify: nil}, reply_to) do
    GenServer.reply(reply_to, :ok)
  end

  defp send_notification(%{notify: {pid, msg}}, reply_to) when is_pid(pid),
    do: send(pid, {msg, reply_to})

  defp send_notification(%{notify: {pid, msg}}, reply_to) do
    case Process.whereis(pid) do
      nil -> GenServer.reply(reply_to, :ok)
      loc -> send(loc, {msg, reply_to})
    end
  end
end
