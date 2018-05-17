defmodule DeltaCrdt.CausalCrdt do
  use GenServer

  @ship_debounce 200
  @ship_interval 5000
  @gc_interval 10_000

  @type delta :: {k :: integer(), delta :: any()}
  @type delta_interval :: {a :: integer(), b :: integer(), delta :: delta()}

  # @callback new() :: {initial_state :: any, new_causal_context :: list(tuple())}

  # @callback join(
  #             {state1 :: any(), causal_context_1 :: CausalContext.t()},
  #             {state2 :: any(), causal_context_2 :: CausalContext.t()}
  #           ) :: {new_state :: any(), new_causal_context :: CausalContext.t()}

  # @callback value(state :: any()) :: any()

  @moduledoc """
  DeltaCrdt implements Algorithm 2 from `Delta State Replicated Data Types – Almeida et al. 2016`
  which is an anti-entropy algorithm for δ-CRDTs. You can find the original paper here: https://arxiv.org/pdf/1603.01529.pdf
  """

  @doc """
  Start a DeltaCrdt.
  """
  def start_link(crdt_state, notify_pid \\ nil, opts \\ []) do
    GenServer.start_link(__MODULE__, {crdt_state, notify_pid}, opts)
  end

  defmodule State do
    defstruct notify_pid: nil,
              neighbours: MapSet.new(),
              crdt_state: [],
              sequence_number: 0,
              deltas: %{},
              ack_map: %{}
  end

  def init({crdt_state, notify_pid}) do
    DeltaCrdt.Periodic.start_link(:ship_interval_or_state, @ship_interval)
    DeltaCrdt.Periodic.start_link(:garbage_collect_deltas, @gc_interval)

    {:ok,
     %State{
       notify_pid: notify_pid,
       crdt_state: crdt_state
     }}
  end

  defp ship_state_to_neighbour(neighbour, state) do
    remote_acked = Map.get(state.ack_map, neighbour, 0)

    if Enum.empty?(state.deltas) || Map.keys(state.deltas) |> Enum.min() > remote_acked do
      send(neighbour, {:delta, self(), state.crdt_state, state.sequence_number})
    else
      state.deltas
      |> Enum.filter(fn {i, _delta} -> remote_acked <= i && i < state.sequence_number end)
      |> case do
        [] ->
          nil

        deltas ->
          delta_interval =
            deltas
            |> Enum.map(fn {_i, delta} -> delta end)
            |> Enum.reduce(fn delta, delta_interval ->
              DeltaCrdt.JoinSemilattice.join(delta_interval, delta)
            end)

          if(remote_acked < state.sequence_number) do
            send(neighbour, {:delta, self(), delta_interval, state.sequence_number})
          end
      end
    end
  end

  def handle_info(:ship_interval_or_state_to_all, state) do
    state.neighbours
    |> Enum.each(fn n -> ship_state_to_neighbour(n, state) end)

    {:noreply, state}
  end

  def handle_info(:ship_interval_or_state, %{neighbours: neighbours} = state) do
    if Enum.empty?(neighbours) do
      {:noreply, state}
    else
      neighbour = neighbours |> Enum.random()
      ship_state_to_neighbour(neighbour, state)
    end

    {:noreply, state}
  end

  def handle_info(:garbage_collect_deltas, state) do
    if Enum.empty?(state.neighbours) do
      {:noreply, state}
    else
      l =
        state.neighbours
        |> Enum.filter(fn neighbour -> Map.has_key?(state.ack_map, neighbour) end)
        |> Enum.map(fn neighbour -> Map.get(state.ack_map, neighbour, 0) end)
        |> Enum.min(fn -> 0 end)

      new_deltas = state.deltas |> Enum.filter(fn {i, _delta} -> i >= l end) |> Enum.into(%{})
      {:noreply, %{state | deltas: new_deltas}}
    end
  end

  def handle_info({:add_neighbours, pids}, state) do
    new_neighbours = pids |> Enum.into(MapSet.new()) |> MapSet.union(state.neighbours)

    {:noreply, %{state | neighbours: new_neighbours}}
  end

  def handle_info({:add_neighbour, neighbour_pid}, state) do
    new_neighbours = MapSet.put(state.neighbours, neighbour_pid)
    {:noreply, %{state | neighbours: new_neighbours}}
  end

  def handle_info(
        {:delta, neighbour,
         %{state: %DeltaCrdt.Causal{state: _d_s, context: delta_c}} = delta_interval, n},
        %{crdt_state: %{state: %DeltaCrdt.Causal{state: _s, context: c}}} = state
      ) do
    last_known_states =
      Enum.reduce(c, %{}, fn {n, v}, acc ->
        Map.update(acc, n, v, fn y -> Enum.max([v, y]) end)
      end)

    first_new_states =
      Enum.reduce(delta_c, %{}, fn {n, v}, acc ->
        Map.update(acc, n, v, fn y -> Enum.min([v, y]) end)
      end)

    reject =
      first_new_states
      |> Enum.find(false, fn {n, v} -> Map.get(last_known_states, n, 0) + 1 < v end)

    if reject do
      send(neighbour, {:ack, self(), n})
      {:noreply, state}
    else
      new_crdt_state = DeltaCrdt.JoinSemilattice.join(state.crdt_state, delta_interval)
      new_deltas = Map.put(state.deltas, state.sequence_number, delta_interval)
      new_sequence_number = state.sequence_number + 1

      case state.notify_pid do
        {pid, msg} -> send(pid, msg)
        _ -> nil
      end

      Process.send_after(self(), {:ship, new_sequence_number}, @ship_debounce)

      new_state = %{
        state
        | crdt_state: new_crdt_state,
          deltas: new_deltas,
          sequence_number: new_sequence_number
      }

      send(neighbour, {:ack, self(), n})
      {:noreply, new_state}
    end
  end

  def handle_info({:ack, neighbour, n}, state) do
    if(Map.get(state.ack_map, neighbour, 0) >= n) do
      {:noreply, state}
    else
      new_ack_map = Map.put(state.ack_map, neighbour, n)
      {:noreply, %{state | ack_map: new_ack_map}}
    end
  end

  def handle_info({:ship, s}, %{sequence_number: s, neighbours: neighbours} = state) do
    Enum.each(neighbours, fn n -> ship_state_to_neighbour(n, state) end)

    {:noreply, state}
  end

  def handle_info({:ship, _s}, state), do: {:noreply, state}

  def handle_call({:read, module}, _from, state) do
    ret = apply(module, :read, [state.crdt_state])
    {:reply, ret, state}
  end

  def handle_call({:operation, operation}, _from, state) do
    new_state = handle_operation(state, operation)
    {:reply, :ok, new_state}
  end

  def handle_cast({:operation, operation}, state) do
    new_state = handle_operation(state, operation)
    {:noreply, new_state}
  end

  def handle_operation(state, {module, function, args}) do
    delta = apply(module, function, [state.crdt_state, self()] ++ args)
    new_crdt_state = DeltaCrdt.JoinSemilattice.join(state.crdt_state, delta)
    new_deltas = Map.put(state.deltas, state.sequence_number, delta)

    new_sequence_number = state.sequence_number + 1

    new_state =
      state
      |> Map.put(:deltas, new_deltas)
      |> Map.put(:crdt_state, new_crdt_state)
      |> Map.put(:sequence_number, new_sequence_number)

    case state.notify_pid do
      {pid, msg} -> send(pid, msg)
      _ -> nil
    end

    Process.send_after(self(), {:ship, new_sequence_number}, @ship_debounce)

    new_state
  end
end

defmodule DeltaCrdt.Periodic do
  use GenServer

  def start_link(message, interval) do
    parent = self()
    GenServer.start_link(__MODULE__, {parent, message, interval})
  end

  def init({parent, message, interval}) do
    Process.send_after(self(), :tick, interval)
    {:ok, {parent, message, interval}}
  end

  def handle_info(:tick, {parent, message, interval}) do
    send(parent, message)
    Process.send_after(self(), :tick, interval)
    {:noreply, {parent, message, interval}}
  end
end
