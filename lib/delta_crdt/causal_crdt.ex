defmodule DeltaCrdt.CausalCrdt do
  use GenServer

  @ship_interval 10_000
  @gc_interval 120_000

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
  def start_link(crdt_state, opts \\ []) do
    GenServer.start_link(__MODULE__, crdt_state, opts)
  end

  defmodule State do
    # crdt_id: nil,
    # crdt_name: nil,
    defstruct neighbours: [],
              crdt_state: [],
              sequence_number: 0,
              deltas: %{},
              ack_map: %{}
  end

  def init(crdt_state) do
    DeltaCrdt.Periodic.start_link(:ship_interval_or_state, @ship_interval)
    DeltaCrdt.Periodic.start_link(:garbage_collect_deltas, @gc_interval)

    {:ok,
     %State{
       crdt_state: crdt_state
     }}
  end

  def handle_info({:add_neighbour, neighbour_pid}, state) do
    # monitor_neighbours(neighbour_pid)
    {:noreply, %{state | neighbours: [neighbour_pid | state.neighbours]}}
  end

  # def handle_info({:remove_neighbour, pid}, state) do
  # end

  # def handle_info({:DOWN, pid}, state), do: handle_info({:remove_neighbour, pid})

  # defp monitor_neighbours([neighbour | neighbours]) do
  #   Process.monitor(neighbour)
  #   monitor_neighbours(neighbours)
  # end

  # defp monitor_neighbours(neighbour), do: monitor_neighbours([neighbour])

  def handle_info(:ship_interval_or_state_to_all, state) do
    state.neighbours |> Enum.each(fn neighbour -> ship_state_to_neighbour(neighbour, state) end)
    {:noreply, state}
  end

  defp ship_state_to_neighbour(neighbour, state) do
    remote_acked = Map.get(state.ack_map, neighbour, 0)

    delta_interval =
      if Enum.empty?(state.deltas) || Map.keys(state.deltas) |> Enum.min() > remote_acked do
        state.crdt_state
      else
        state.deltas
        |> Enum.filter(fn {i, _delta} -> remote_acked <= i && i < state.sequence_number end)
        |> Enum.map(fn {_i, delta} -> delta end)
        |> Enum.reduce(fn delta, delta_interval ->
          DeltaCrdt.JoinSemilattice.join(delta_interval, delta)
        end)
      end

    if(remote_acked < state.sequence_number) do
      send(neighbour, {:delta, self(), delta_interval, state.sequence_number})
    end
  end

  def handle_info(:ship_interval_or_state, state) do
    neighbour = state.neighbours |> Enum.random()
    ship_state_to_neighbour(neighbour, state)

    {:noreply, state}
  end

  def handle_info(:garbage_collect_deltas, state) do
    l =
      state.neighbours
      |> Enum.filter(fn neighbour -> Map.has_key?(state.ack_map, neighbour) end)
      |> Enum.map(fn neighbour -> Map.get(state.ack_map, neighbour, 0) end)
      |> Enum.min()

    new_deltas = state.deltas |> Enum.filter(fn {i, _delta} -> i >= l end)
    {:noreply, %{state | deltas: new_deltas}}
  end

  def handle_info(
        {:delta, neighbour,
         %{crdt: %DeltaCrdt.Causal{state: _d_s, context: delta_c}} = delta_interval, n},
        %{crdt_state: %{crdt: %DeltaCrdt.Causal{state: _s, context: c}}} = state
      ) do
    last_known_state =
      Enum.map(c, fn
        {^neighbour, val} -> val
        _ -> 0
      end)
      |> Enum.max(fn -> 0 end)

    newest_state =
      Enum.map(delta_c, fn
        {^neighbour, val} -> val
        _ -> 0
      end)
      |> Enum.max(fn -> 0 end)

    new_state =
      if(newest_state - 1 <= last_known_state) do
        new_crdt_state = DeltaCrdt.JoinSemilattice.join(state.crdt_state, delta_interval)
        new_deltas = Map.put(state.deltas, state.sequence_number, delta_interval)
        new_sequence_number = state.sequence_number + 1

        %{
          state
          | crdt_state: new_crdt_state,
            deltas: new_deltas,
            sequence_number: new_sequence_number
        }
      else
        state
      end

    send(neighbour, {:ack, self(), n})

    {:noreply, new_state}
  end

  def handle_info({:ack, neighbour, n}, state) do
    if(Map.get(state.ack_map, neighbour, 0) >= n) do
      {:noreply, state}
    else
      new_ack_map = Map.put(state.ack_map, neighbour, n)
      {:noreply, %{state | ack_map: new_ack_map}}
    end
  end

  def handle_cast({:operation, {module, function, args}}, state) do
    delta = apply(module, function, [state.crdt_state, self()] ++ args)
    new_crdt_state = DeltaCrdt.JoinSemilattice.join(state.crdt_state, delta)
    new_deltas = Map.put(state.deltas, state.sequence_number, delta)

    new_sequence_number = state.sequence_number + 1

    new_state =
      state
      |> Map.put(:deltas, new_deltas)
      |> Map.put(:crdt_state, new_crdt_state)
      |> Map.put(:sequence_number, new_sequence_number)

    {:noreply, new_state}
  end

  def handle_call(:read, _from, state) do
    ret = DeltaCrdt.JoinSemilattice.read(state.crdt_state)
    # ret = apply(module, function, [state.crdt_state] ++ args)
    {:reply, ret, state}
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
