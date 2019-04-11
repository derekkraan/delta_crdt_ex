defmodule DeltaCrdt.CausalCrdt do
  use GenServer

  require Logger

  @type delta :: {k :: integer(), delta :: any()}
  @type delta_interval :: {a :: integer(), b :: integer(), delta :: delta()}

  @moduledoc false

  defstruct node_id: nil,
            name: nil,
            on_diffs: nil,
            storage_module: nil,
            crdt_module: nil,
            crdt_state: nil,
            merkle_tree: %MerkleTree{},
            sequence_number: 0,
            neighbours: MapSet.new()

  defmacrop strip_continue(tuple) do
    if System.otp_release() |> String.to_integer() > 20 do
      tuple
    else
      quote do
        case unquote(tuple) do
          {tup1, tup2, {:continue, _}} -> {tup1, tup2}
        end
      end
    end
  end

  ### GenServer callbacks

  def init(opts) do
    DeltaCrdt.Periodic.start_link(:sync, Keyword.get(opts, :sync_interval))

    Process.flag(:trap_exit, true)

    crdt_module = Keyword.get(opts, :crdt_module)

    initial_state = %__MODULE__{
      node_id: :rand.uniform(1_000_000_000),
      name: Keyword.get(opts, :name),
      on_diffs: Keyword.get(opts, :on_diffs, fn _diffs -> nil end),
      storage_module: Keyword.get(opts, :storage_module),
      crdt_module: crdt_module,
      crdt_state: crdt_module.new() |> crdt_module.compress_dots()
    }

    strip_continue({:ok, initial_state, {:continue, :read_storage}})
  end

  def handle_continue(:read_storage, state) do
    {:noreply, read_from_storage(state)}
  end

  # TODO this won't sync everything anymore, since syncing is now a 2-step process.
  # Figure out how to do this properly. Maybe with a `receive` block.
  def terminate(_reason, state) do
    sync_interval_or_state_to_all(state)
  end

  defp read_from_storage(%{storage_module: nil} = state) do
    state
  end

  defp read_from_storage(state) do
    case state.storage_module.read(state.name) do
      nil ->
        state

      {node_id, sequence_number, crdt_state, merkle_tree} ->
        Map.put(state, :sequence_number, sequence_number)
        |> Map.put(:crdt_state, crdt_state)
        |> Map.put(:merkle_tree, merkle_tree)
        |> Map.put(:node_id, node_id)
        |> remove_crdt_state_keys()
    end
  end

  defp remove_crdt_state_keys(state) do
    %{state | crdt_state: Map.put(state.crdt_state, :keys, MapSet.new())}
  end

  defp write_to_storage(%{storage_module: nil} = state) do
    state
  end

  defp write_to_storage(state) do
    :ok =
      state.storage_module.write(
        state.name,
        {state.node_id, state.sequence_number, state.crdt_state, state.merkle_tree}
      )

    state
  end

  defp sync_state_to_neighbour(neighbour, _state) when neighbour == self(), do: nil

  defp sync_state_to_neighbour(neighbour, state) do
    send(neighbour, {:get_diff_keys, state.merkle_tree, state.crdt_state.dots, self()})
    {neighbour, state.sequence_number}
  end

  defp sync_interval_or_state_to_all(state) do
    Enum.filter(state.neighbours, &process_alive?/1)
    |> Enum.each(fn n -> sync_state_to_neighbour(n, state) end)

    :ok
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:set_neighbours, neighbours}, state) do
    state = %{state | neighbours: MapSet.new(neighbours)}

    sync_interval_or_state_to_all(state)

    {:noreply, state}
  end

  def handle_info({:get_diff_keys, merkle_tree, dots, from}, state) do
    case MerkleTree.diff(state.merkle_tree, merkle_tree) do
      [] ->
        nil

      diff_keys ->
        send(from, {:diff_keys, diff_keys, dots, self()})
    end

    {:noreply, state}
  end

  def handle_info({:diff_keys, diff_keys, dots, from}, state) when is_list(diff_keys) do
    diff = %{state.crdt_state | dots: dots, value: Map.take(state.crdt_state.value, diff_keys)}
    send(from, {:diff, diff, diff_keys})

    {:noreply, state}
  end

  def handle_info({:diff, diff, keys}, state) do
    new_state = update_state_with_delta(state, diff, keys)
    {:noreply, new_state}
  end

  def handle_call(:sync, _from, state) do
    sync_interval_or_state_to_all(state)

    {:reply, :ok, state}
  end

  def handle_call(:read, _from, %{crdt_module: crdt_module, crdt_state: crdt_state} = state),
    do: {:reply, {crdt_module, crdt_state}, state}

  def handle_call({:operation, operation}, _from, state) do
    {:reply, :ok, handle_operation(operation, state)}
  end

  def handle_cast({:operation, operation}, state) do
    {:noreply, handle_operation(operation, state)}
  end

  defp handle_operation({function, [key | rest_args]}, state) do
    delta =
      apply(state.crdt_module, function, [key | rest_args] ++ [state.node_id, state.crdt_state])

    update_state_with_delta(state, delta, [key])
  end

  defp diff(old_state, new_state, keys) do
    old = old_state.crdt_module.read(old_state.crdt_state, keys)
    new = old_state.crdt_module.read(new_state.crdt_state, keys)

    Enum.flat_map(keys, fn key ->
      case {Map.get(old, key), Map.get(new, key)} do
        {old, old} -> []
        {_old, nil} -> [{:remove, key}]
        {_old, new} -> [{:add, key, new}]
      end
    end)
  end

  defp update_state_with_delta(state, delta, keys) do
    new_crdt_state = state.crdt_module.join(state.crdt_state, delta, keys)
    diffs = diff(state, Map.put(state, :crdt_state, new_crdt_state), keys)

    new_merkle_tree =
      Enum.reduce(diffs, state.merkle_tree, fn
        {:add, key, value}, tree -> MerkleTree.put_in_tree(tree, {key, value})
        {:remove, key}, tree -> MerkleTree.remove_key(tree, key)
      end)

    case diffs do
      [] -> nil
      diffs -> state.on_diffs.(diffs)
    end

    Map.put(state, :crdt_state, new_crdt_state)
    |> Map.put(:merkle_tree, new_merkle_tree)
    |> write_to_storage()
  end

  defp process_alive?({name, n}) when n == node(), do: Process.whereis(name) != nil

  defp process_alive?({name, n}) do
    Enum.member?(Node.list(), n) && :rpc.call(n, Process, :whereis, [name]) != nil
  end

  defp process_alive?(pid) when node(pid) == node(), do: Process.alive?(pid)

  defp process_alive?(pid) do
    Enum.member?(Node.list(), node(pid)) && :rpc.call(node(pid), Process, :alive?, [pid])
  end
end
