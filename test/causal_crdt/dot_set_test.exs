defmodule DeltaCrdt.CausalCrdt.DotSetTest do
  use ExUnit.Case, async: true

  describe ".join/2" do
    test "an element has been added" do
      s_1 = [{1, 1, "a"}]
      c_1 = %{1 => 1, 2 => 1}
      s_2 = [{1, 1, "a"}, {2, 2, "b"}]
      c_2 = %{1 => 1, 2 => 2}

      assert {[{1, 1, "a"}, {2, 2, "b"}], _context} =
               DeltaCrdt.CausalCrdt.DotSet.join({s_1, c_1}, {s_2, c_2})
    end

    test "an element has been removed" do
      s_1 = [{1, 1, "a"}, {2, 2, "b"}]
      c_1 = %{1 => 1, 2 => 2}
      s_2 = [{1, 1, "a"}]
      c_2 = %{1 => 1, 2 => 3}

      assert {[{1, 1, "a"}], _context} = DeltaCrdt.CausalCrdt.DotSet.join({s_1, c_1}, {s_2, c_2})
    end
  end

  describe ".value/1" do
    test "just returns the dots" do
      assert 1 = DeltaCrdt.CausalCrdt.DotSet.value(1)
    end
  end
end
