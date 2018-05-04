defmodule DeltaCrdt.CausalContextTest do
  use ExUnit.Case, async: true

  describe ".merge/2" do
    test "can merge causal contexts" do
      a = %{a: 1, b: 2}
      b = %{a: 2, b: 1, c: 3}
      assert %{a: 2, b: 2, c: 3} = DeltaCrdt.CausalContext.merge(a, b)
    end
  end

  describe ".next/2" do
    test "can compute the next context for node i" do
      context = %{a: 1, b: 2}
      assert %{a: 2, b: 2} = DeltaCrdt.CausalContext.next(context, :a)
    end

    test "can compute for not-existing nodes" do
      context = %{a: 1, b: 2}
      assert %{a: 1, b: 2, c: 0} = DeltaCrdt.CausalContext.next(context, :c)
    end
  end
end
