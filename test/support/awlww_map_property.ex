defmodule AWLWWMapProperty do
  use ExUnitProperties
  alias DeltaCrdt.AWLWWMap

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
end
