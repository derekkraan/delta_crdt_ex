defmodule AWLWWMapDotsTest do
  use ExUnit.Case
  use ExUnitProperties
  alias DeltaCrdt.AWLWWMap

  defp dot do
    ExUnitProperties.gen all node_id <- string(:ascii),
                             sequence_number <- positive_integer() do
      {node_id, sequence_number}
    end
  end

  describe ".strict_expansion?/2" do
    property "dots are always own strict expansion" do
      check all dots <- list_of(dot(), min_length: 1) do
        assert AWLWWMap.Dots.strict_expansion?(Enum.into(dots, %{}), MapSet.new(dots))
      end
    end

    property "increase number by one" do
      check all dots <- list_of(dot(), min_length: 1) do
        [{node_id, seq} | _rest] = dots

        assert AWLWWMap.Dots.strict_expansion?(
                 Enum.into(dots, %{}),
                 MapSet.new([{node_id, seq + 1}])
               )
      end
    end

    # property "increase number by two" do
    #   check all dots <- list_of(dot(), min_length: 1) do
    #     [{node_id, seq} | _rest] = dots

    #     refute AWLWWMap.Dots.strict_expansion?(
    #              Enum.into(dots, %{}),
    #              MapSet.new([{node_id, seq + 2}])
    #            )
    #   end
    # end
  end
end
