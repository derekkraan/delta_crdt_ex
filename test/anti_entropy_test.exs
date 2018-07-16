defmodule AntiEntropyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DeltaCrdt.{CausalContext, AntiEntropy}

  describe ".is_strict_expansion/2" do
    test "strict expansion" do
      c = CausalContext.new([{1, 0}, {1, 1}]) |> CausalContext.compress()
      delta_c = CausalContext.new([{1, 2}]) |> CausalContext.compress()

      assert true == AntiEntropy.is_strict_expansion(c, delta_c)
      assert true == AntiEntropy.is_strict_expansion(delta_c, c)
    end

    test "not an expansion" do
      c = CausalContext.new([{1, 0}, {1, 1}]) |> CausalContext.compress()
      delta_c = CausalContext.new([{1, 3}]) |> CausalContext.compress()

      assert false == AntiEntropy.is_strict_expansion(c, delta_c)
      assert true == AntiEntropy.is_strict_expansion(delta_c, c)
    end

    test "not an expansion in both directions" do
      c = CausalContext.new([{1, 0}, {1, 1}, {2, 4}]) |> CausalContext.compress()
      delta_c = CausalContext.new([{1, 3}, {2, 2}]) |> CausalContext.compress()

      assert false == AntiEntropy.is_strict_expansion(c, delta_c)
      assert false == AntiEntropy.is_strict_expansion(delta_c, c)
    end
  end
end
