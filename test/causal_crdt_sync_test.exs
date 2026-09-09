defmodule CausalCrdtSyncTest do
  use ExUnit.Case, async: true

  alias DeltaCrdt.AWLWWMap
  alias DeltaCrdt.CausalCrdt.Diff

  @peer_name __MODULE__.Peer

  test "initial sync waits for an ACK before starting another round" do
    crdt = start_crdt()
    DeltaCrdt.put(crdt, :sample, :first)
    DeltaCrdt.set_neighbours(crdt, [self()])
    assert DeltaCrdt.to_map(crdt) == %{sample: :first}
    assert_receive {:diff, %Diff{originator: ^crdt}}

    for _ <- 1..5, do: tick(crdt)
    refute_receive {:diff, %Diff{originator: ^crdt}}, 0

    send(crdt, {:ack_diff, self()})
    tick(crdt)
    assert_receive {:diff, %Diff{originator: ^crdt}}
  end

  test "a get_diff reply cannot acknowledge the following sync round" do
    crdt = start_crdt()
    peer = self()
    DeltaCrdt.put(crdt, :sample, :first)
    DeltaCrdt.set_neighbours(crdt, [peer])
    assert_receive {:diff, %Diff{originator: ^crdt} = diff}

    :ok = :sys.suspend(crdt)

    try do
      # A peer finishing comparison sends get_diff followed by an ACK. Queue a
      # tick after them: a redundant self-ACK from get_diff would arrive last,
      # clearing the marker for the round started by this tick.
      send(crdt, {:get_diff, %Diff{diff | from: peer, to: crdt}, [:sample]})
      send(crdt, {:ack_diff, peer})
      send(crdt, :sync)
    after
      :ok = :sys.resume(crdt)
    end

    assert_receive {:diff, %AWLWWMap{} = delta, [:sample]}
    assert AWLWWMap.read(delta) == %{sample: :first}
    assert_receive {:diff, %Diff{originator: ^crdt}}

    tick(crdt)
    refute_receive {:diff, %Diff{originator: ^crdt}}, 0
  end

  test "removing and re-adding the same live unacknowledged peer starts a new round" do
    crdt = start_crdt()
    DeltaCrdt.set_neighbours(crdt, [self()])
    DeltaCrdt.to_map(crdt)
    assert_receive {:diff, %Diff{originator: ^crdt}}

    DeltaCrdt.set_neighbours(crdt, [])
    DeltaCrdt.to_map(crdt)
    DeltaCrdt.set_neighbours(crdt, [self()])
    DeltaCrdt.to_map(crdt)

    assert_receive {:diff, %Diff{originator: ^crdt}}
    tick(crdt)
    refute_receive {:diff, %Diff{originator: ^crdt}}, 0
  end

  test "a replacement process under the same named peer can receive a new round" do
    crdt = start_crdt()
    peer = start_peer()
    neighbour = {@peer_name, node()}
    DeltaCrdt.set_neighbours(crdt, [neighbour])
    DeltaCrdt.to_map(crdt)
    assert_receive {:peer_diff, ^peer, %Diff{originator: ^crdt}}

    monitor = Process.monitor(peer)
    Process.exit(peer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^peer, :killed}

    # Our DOWN and the CRDT's DOWN arrive independently. Wait for its handler
    # before registering the replacement, so this exercises restart recovery.
    eventually(fn ->
      refute Map.has_key?(:sys.get_state(crdt).neighbour_monitors, neighbour)
    end)

    replacement = start_peer()
    tick(crdt)
    assert_receive {:peer_diff, ^replacement, %Diff{originator: ^crdt}}
  end

  test "replicas converge across Merkle continuation after adds, updates, and deletes" do
    # Exercise Merkle continuation without truncating the synchronization.
    left = start_crdt(max_sync_size: :infinite)
    right = start_crdt(max_sync_size: :infinite)
    initial = Map.new(1..512, &{&1, :first})
    DeltaCrdt.merge(left, initial)
    DeltaCrdt.set_neighbours(left, [right])
    DeltaCrdt.set_neighbours(right, [left])
    assert_converged([left, right], initial)

    DeltaCrdt.put(right, 1, :second)
    assert_converged([left, right], Map.put(initial, 1, :second))

    DeltaCrdt.drop(left, Map.keys(initial))
    assert_converged([left, right], %{})
  end

  defp start_crdt(opts \\ []),
    do:
      start_supervised!(%{
        id: make_ref(),
        start: {DeltaCrdt, :start_link, [AWLWWMap, Keyword.put_new(opts, :sync_interval, 60_000)]}
      })

  defp tick(crdt) do
    send(crdt, :sync)
    # Both messages come from this process; the read replies after the tick.
    DeltaCrdt.to_map(crdt)
  end

  defp start_peer do
    parent = self()
    peer = spawn(fn -> forward_diffs(parent) end)
    on_exit(fn -> Process.exit(peer, :kill) end)
    Process.register(peer, @peer_name)
    peer
  end

  defp forward_diffs(parent) do
    receive do
      {:diff, diff} ->
        send(parent, {:peer_diff, self(), diff})
        forward_diffs(parent)
    end
  end

  defp assert_converged(crdts, expected),
    do:
      eventually(fn ->
        for crdt <- crdts, do: tick(crdt)
        for crdt <- crdts, do: assert(DeltaCrdt.to_map(crdt) == expected)
      end)

  defp eventually(fun, retries \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, retries) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      eventually(fun, retries - 1)
  end
end
