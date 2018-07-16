defmodule DeltaCrdt.AntiEntropy do
  @moduledoc false

  def is_strict_expansion(c, delta_c) do
    last_known_states = c.maxima

    first_new_states =
      Enum.reduce(delta_c.dots, %{}, fn {n, v}, acc ->
        Map.update(acc, n, v, fn y -> Enum.min([v, y]) end)
      end)

    Enum.all?(first_new_states, fn {n, first} ->
      case Map.get(last_known_states, n) do
        nil -> true
        last -> first <= last + 1
      end
    end)
  end
end
