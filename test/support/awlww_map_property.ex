defmodule AWLWWMapProperty do
  use ExUnitProperties
  alias DeltaCrdt.{AWLWWMap}

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
    ExUnitProperties.gen all operation <- one_of([:add, :remove]),
                             key <- binary(),
                             val <- binary(),
                             node_id <- integer() do
      case operation do
        :add ->
          fn
            state -> AWLWWMap.add(key, val, node_id, state)
          end

        :remove ->
          fn state -> AWLWWMap.remove(key, node_id, state) end
      end
    end
  end
end
