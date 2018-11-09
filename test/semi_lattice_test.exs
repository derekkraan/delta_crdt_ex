defmodule SemiLatticeTest do
  alias DeltaCrdt.{AWLWWMap, SemiLattice}

  use ExUnit.Case, async: true
  use ExUnitProperties

  describe ".minimum_delta/2" do
    property "returns :bottom when delta already applied" do
      state = AWLWWMap.new()

      check all key <- term(),
                val <- term(),
                node_id <- term() do
        delta = AWLWWMap.add(key, val, node_id, state)
        new_state = SemiLattice.join(state, delta)
        assert {_state, ^delta} = SemiLattice.minimum_delta(state, delta)
        assert {_state, :bottom} = SemiLattice.minimum_delta(new_state, delta)
      end
    end

    property "returns :bottom when delta already applied (more complex example)" do
      op =
        ExUnitProperties.gen all key <- term(),
                                 val <- term(),
                                 node_id <- term() do
          {key, val, node_id}
        end

      state = AWLWWMap.new()

      check all ops <- list_of(op, length: 2) do
        deltas =
          Enum.map(ops, fn {key, val, node_id} -> AWLWWMap.add(key, val, node_id, state) end)

        [d1, d2] = deltas

        delta_interval = SemiLattice.join(d1, d2)

        new_state =
          SemiLattice.join(state, d1)
          |> SemiLattice.join(d2)

        assert {_state, :bottom} = SemiLattice.minimum_delta(new_state, delta_interval)

        # assert d2 == SemiLattice.minimum_delta(new_state, delta_interval)
      end
    end

    property "can calculate join decomposition of a delta" do
      check all operations <- list_of(AWLWWMapProperty.random_operation(), min_length: 10) do
        {ops1, ops2} = Enum.split(operations, 5)

        half_state =
          Enum.reduce(ops1, AWLWWMap.new(), fn op, st ->
            delta = op.(st)
            SemiLattice.join(st, delta)
          end)
          |> SemiLattice.compress()

        total_delta =
          Enum.reduce(operations, AWLWWMap.new(), fn operation, state ->
            delta = operation.(state)
            SemiLattice.join(state, delta)
          end)

        minimum_delta =
          AWLWWMap.join_decomposition(total_delta)
          |> Enum.filter(fn delta -> AWLWWMap.strict_expansion?(half_state, delta) end)

        # IO.inspect({Enum.count(operations), Enum.count(minimum_delta)})
        # IO.inspect({half_state, minimum_delta})

        assert Enum.count(minimum_delta) <= Enum.count(operations) - 5

        state_from_min_delta = Enum.reduce([half_state | minimum_delta], &SemiLattice.join/2)

        assert AWLWWMap.read(total_delta) == AWLWWMap.read(state_from_min_delta)
      end
    end

    @tag :skip
    property "can calculate partial minimum delta" do
      op =
        ExUnitProperties.gen all key <- term(),
                                 val <- term(),
                                 node_id <- term() do
          {key, val, node_id}
        end

      state = AWLWWMap.new()

      check all ops <- list_of(op, length: 2) do
        deltas =
          Enum.map(ops, fn {key, val, node_id} -> AWLWWMap.add(key, val, node_id, state) end)

        [d1, d2] = deltas

        delta_interval = SemiLattice.join(d1, d2)

        new_state = SemiLattice.join(state, d1)

        assert d2 == SemiLattice.minimum_delta(new_state, delta_interval)
      end
    end
  end
end
