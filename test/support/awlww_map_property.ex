defmodule AWLWWMapProperty do
  use ExUnitProperties
  alias DeltaCrdt.{AWLWWMap, SemiLattice}

  def add_operation do
    ExUnitProperties.gen all key <- binary(),
                             val <- binary(),
                             node_id <- integer() do
      fn state -> AWLWWMap.add(key, val, node_id, state) end
    end
  end

  def remove_operation do
    ExUnitProperties.gen all key <- binary(),
                             node_id <- integer() do
      fn state -> AWLWWMap.remove(key, node_id, state) end
    end
  end

  def random_operation do
    ExUnitProperties.gen all add <- add_operation(),
                             remove <- remove_operation() do
      Enum.random([add, remove])
    end
  end

  def half_state_full_delta do
    ExUnitProperties.gen all ops <- list_of(random_operation(), length: 30) do
      {ops1, ops2} = Enum.split(ops, 15)

      half_state =
        Enum.reduce(ops1, AWLWWMap.new(), fn op, st ->
          delta = op.(st)
          SemiLattice.join(st, delta)
        end)
        |> SemiLattice.compress()

      full_delta =
        Enum.reduce(ops, AWLWWMap.new(), fn op, st ->
          delta = op.(st)
          SemiLattice.join(st, delta)
        end)

      {half_state, full_delta}
    end
  end
end
