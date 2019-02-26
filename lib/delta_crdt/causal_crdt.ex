defmodule DeltaCrdt.CausalCrdt do
  use GenServer

  require Logger

  @outstanding_ack_timeout 20_000

  @ship_after_x_deltas 100
  @gc_interval 10_000

  @type delta :: {k :: integer(), delta :: any()}
  @type delta_interval :: {a :: integer(), b :: integer(), delta :: delta()}

  @opaque storage_format :: {crdt_state :: term(), sequence_number :: integer()}

  @moduledoc false

  defstruct node_id: nil,
            notify: nil,
            storage_module: nil,
            crdt_module: nil,
            crdt_state: nil,
            shipped_sequence_number: 0,
            sequence_number: 0,
            ship_debounce: 0,
            deltas: %{},
            ack_map: %{},
            neighbours: MapSet.new(),
            outstanding_acks: %{}

  ### GenServer callbacks

  def init(opts) do
    DeltaCrdt.Periodic.start_link(:garbage_collect, @gc_interval)
    DeltaCrdt.Periodic.start_link(:sync, Keyword.get(opts, :sync_interval))
    DeltaCrdt.Periodic.start_link(:try_ship_client, Keyword.get(opts, :ship_interval))

    Process.flag(:trap_exit, true)

    crdt_module = Keyword.get(opts, :crdt_module)

    initial_state =
      %__MODULE__{
        node_id: Keyword.get(opts, :name, :rand.uniform(1_000_000_000)),
        notify: Keyword.get(opts, :notify),
        storage_module: Keyword.get(opts, :storage_module),
        crdt_module: crdt_module,
        ship_debounce: Keyword.get(opts, :ship_debounce),
        crdt_state: crdt_module.new() |> crdt_module.compress_dots()
      }
      |> read_from_storage()

    {:ok, initial_state}
  end

  def terminate(_reason, state) do
    sync_interval_or_state_to_all(%{state | outstanding_acks: %{}})
  end

  defp read_from_storage(%{storage_module: nil} = state) do
    state
  end

  defp read_from_storage(state) do
    case state.storage_module.read(state.node_id) do
      nil ->
        state

      {sequence_number, crdt_state} ->
        Map.put(state, :sequence_number, sequence_number)
        |> Map.put(:crdt_state, crdt_state)
    end
  end

  defp write_to_storage(%{storage_module: nil} = state) do
    state
  end

  defp write_to_storage(state) do
    :ok = state.storage_module.write(state.node_id, {state.sequence_number, state.crdt_state})
    state
  end

  defp resolve_neighbour(neighbour) when is_pid(neighbour), do: neighbour

  defp resolve_neighbour({_name, _node_ref} = ref), do: GenServer.whereis(ref)

  defp sync_state_to_neighbour(neighbour, _state) when neighbour == self(), do: nil

  defp sync_state_to_neighbour(neighbour, state) do
    remote_acked = Map.get(state.ack_map, neighbour, 0)

    if Enum.min(Map.keys(state.deltas), fn -> state.sequence_number end) > remote_acked do
      send(
        neighbour,
        {:delta, {self(), neighbour, state.crdt_state}, state.sequence_number}
      )

      {neighbour, state.sequence_number}
    else
      neighbour_pid = resolve_neighbour(neighbour)

      Enum.filter(state.deltas, fn
        {_i, {^neighbour_pid, _delta}} -> false
        _ -> true
      end)
      |> Enum.filter(fn {i, _delta} -> remote_acked <= i && i < state.sequence_number end)
      |> case do
        [] ->
          nil

        deltas ->
          if(remote_acked < state.sequence_number) do
            delta_interval =
              Enum.map(deltas, fn {_i, {_from, delta}} -> delta end)
              |> Enum.reduce(fn delta, delta_interval ->
                state.crdt_module.join(delta_interval, delta)
              end)

            send(neighbour, {:delta, {self(), neighbour, delta_interval}, state.sequence_number})
            {neighbour, state.sequence_number}
          end
      end
    end
  end

  defp sync_interval_or_state_to_all(state) do
    shipped_to =
      MapSet.difference(state.neighbours, MapSet.new(Map.keys(state.outstanding_acks)))
      |> Enum.map(fn n -> sync_state_to_neighbour(n, state) end)
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

  def handle_info({:set_neighbours, neighbours}, state) do
    state = %{state | neighbours: MapSet.new(neighbours)}

    new_ack_map =
      Enum.filter(state.ack_map, fn {neighbour, _seq} ->
        MapSet.member?(state.neighbours, neighbour)
      end)
      |> Map.new()

    new_outstanding_acks =
      Enum.filter(state.outstanding_acks, fn {neighbour, _ack} ->
        MapSet.member?(state.neighbours, neighbour)
      end)
      |> Map.new()

    state = %{state | ack_map: new_ack_map, outstanding_acks: new_outstanding_acks}

    outstanding_acks = sync_interval_or_state_to_all(state)

    {:noreply, %{state | outstanding_acks: outstanding_acks}}
  end

  def handle_info({:delta, {neighbour, self_ref, delta_interval}, n}, state) do
    %{dots: delta_dots} = delta_interval
    %{crdt_state: %{dots: state_dots}} = state

    strict_expansion = DeltaCrdt.AWLWWMap.Dots.strict_expansion?(state_dots, delta_dots)

    if strict_expansion do
      send(neighbour, {:ack, self_ref, n})

      new_state = apply_delta_interval(state, neighbour, delta_interval)
      {:noreply, new_state}
    else
      send(neighbour, {:nack, self_ref})

      Logger.error(
        "Received delta from neighbour that is not a strict expansion. Sending `nack` to force sending whole state"
      )

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

  def handle_info({:nack, neighbour}, state) do
    new_ack_map = Map.put(state.ack_map, neighbour, 0)
    {:noreply, %{state | ack_map: new_ack_map}}
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

  def handle_call(:delta_count, _from, state) do
    {:reply, Enum.count(state.deltas), state}
  end

  def handle_call(:garbage_collect, _from, state) do
    {:reply, :ok, garbage_collect_deltas(state)}
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

  def handle_call(:sync, _from, state) do
    outstanding_acks = sync_interval_or_state_to_all(state)

    {:reply, :ok, %{state | outstanding_acks: outstanding_acks}}
  end

  def handle_call(:read, _from, %{crdt_module: crdt_module, crdt_state: crdt_state} = state),
    do: {:reply, {crdt_module, crdt_state}, state}

  def handle_call({:operation, operation}, _from, state) do
    {:reply, :ok, handle_operation(operation, state)}
  end

  def handle_cast({:operation, operation}, state) do
    {:noreply, handle_operation(operation, state)}
  end

  defp handle_operation({function, args}, state) do
    delta = apply(state.crdt_module, function, args ++ [state.node_id, state.crdt_state])

    case state.crdt_module.minimum_deltas(delta, state.crdt_state) do
      [] ->
        state

      minimum_deltas ->
        delta = Enum.reduce(minimum_deltas, &state.crdt_module.join/2)

        new_crdt_state = state.crdt_module.join(state.crdt_state, delta)
        new_deltas = Map.put(state.deltas, state.sequence_number, {self(), delta})
        new_sequence_number = state.sequence_number + 1

        Map.put(state, :deltas, new_deltas)
        |> Map.put(:crdt_state, new_crdt_state)
        |> Map.put(:sequence_number, new_sequence_number)
        |> write_to_storage()
    end
  end

  defp max_dots(dots) do
    Enum.reduce(dots, %{}, fn {node_id, val}, map ->
      Map.update(map, node_id, val, fn
        old_val when old_val < val -> val
        old_val -> old_val
      end)
    end)
  end

  defp min_dots(dots) do
    Enum.reduce(dots, %{}, fn {node_id, val}, map ->
      Map.update(map, node_id, val, fn
        old_val when old_val > val -> val
        old_val -> old_val
      end)
    end)
  end

  defp garbage_collect_deltas(state) do
    pid = self()

    neighbours =
      Enum.filter(state.neighbours, fn
        ^pid -> false
        _ -> true
      end)

    if Enum.empty?(neighbours) do
      Map.put(state, :deltas, %{})
    else
      l =
        state.neighbours
        |> Enum.filter(fn neighbour -> Map.has_key?(state.ack_map, neighbour) end)
        |> Enum.map(fn neighbour -> Map.get(state.ack_map, neighbour, 0) end)
        |> Enum.min(fn -> 0 end)

      new_deltas = state.deltas |> Enum.filter(fn {i, _delta} -> i >= l end) |> Map.new()
      Map.put(state, :deltas, new_deltas)
    end
  end

  defp forget_neighbour(state, pid) do
    Map.put(state, :neighbours, MapSet.delete(state.neighbours, pid))
    |> Map.put(:ack_map, Map.delete(state.ack_map, pid))
    |> Map.put(:outstanding_acks, Map.delete(state.outstanding_acks, pid))
  end

  defp apply_delta_interval(state, neighbour, delta_interval) do
    case state.crdt_module.minimum_deltas(delta_interval, state.crdt_state) do
      [] ->
        state

      minimum_deltas ->
        delta = Enum.reduce(minimum_deltas, &state.crdt_module.join/2)

        new_crdt_state = state.crdt_module.join(state.crdt_state, delta)
        new_deltas = Map.put(state.deltas, state.sequence_number, {neighbour, delta})
        new_sequence_number = state.sequence_number + 1

        Map.put(state, :deltas, new_deltas)
        |> Map.put(:crdt_state, new_crdt_state)
        |> Map.put(:sequence_number, new_sequence_number)
        |> write_to_storage()
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
