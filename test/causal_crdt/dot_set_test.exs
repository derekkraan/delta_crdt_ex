defmodule DeltaCrdt.CausalCrdt.DotSetTest do
  use ExUnit.Case, async: true

  describe ".join/2" do
    test "an element has been added" do
      s_1 = [{1, 1}] |> Enum.into(MapSet.new())
      c_1 = %{1 => 1, 2 => 1} |> Enum.into(MapSet.new())
      s_2 = [{1, 1}, {2, 2}] |> Enum.into(MapSet.new())
      c_2 = %{1 => 1, 2 => 2} |> Enum.into(MapSet.new())

      assert [{1, 1}, {2, 2}] =
               DeltaCrdt.CausalCrdt.DotSet.join({s_1, c_1}, {s_2, c_2})
               |> elem(0)
               |> Enum.into([])
    end

    test "an element has been removed" do
      s_1 = [{1, 1}, {2, 2}] |> Enum.into(MapSet.new())
      c_1 = %{1 => 1, 2 => 2} |> Enum.into(MapSet.new())
      s_2 = [{1, 1}] |> Enum.into(MapSet.new())
      c_2 = %{1 => 1, 2 => 2} |> Enum.into(MapSet.new())

      assert [{1, 1}] =
               DeltaCrdt.CausalCrdt.DotSet.join({s_1, c_1}, {s_2, c_2})
               |> elem(0)
               |> Enum.into([])
    end
  end

  describe ".value/1" do
    test "just returns the dots" do
      assert [{:a, 1}, {:b, 2}] =
               DeltaCrdt.CausalCrdt.DotSet.value(Enum.into(%{a: 1, b: 2}, MapSet.new()))
    end
  end
end
