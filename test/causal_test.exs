defmodule DeltaCrdt.CausalTest do
  use ExUnit.Case, async: true

  describe ".next/2" do
    test "can compute the next context for node i" do
      context = %{a: 1, b: 2} |> MapSet.new()
      assert {:a, 2} = DeltaCrdt.Causal.next(context, :a)
    end

    test "can compute for not-existing nodes" do
      context = %{a: 1, b: 2} |> MapSet.new()
      assert {:c, 1} = DeltaCrdt.Causal.next(context, :c)
    end
  end
end
