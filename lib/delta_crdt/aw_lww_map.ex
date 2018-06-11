defmodule DeltaCrdt.AWLWWMap do
  alias DeltaCrdt.{CausalDotMap, AWSet, ORMap}

  def start_link(notify_pid \\ nil, opts \\ []) do
    DeltaCrdt.CausalCrdt.start_link(new(), notify_pid, opts)
  end

  def new(), do: %CausalDotMap{}

  def add(key, val, i, map) do
    {AWSet, :add, [{val, System.system_time(:nanosecond)}]}
    |> ORMap.apply(key, i, map)
  end

  def remove(key, i, map), do: ORMap.remove(key, i, map)

  def clear(i, map), do: ORMap.clear(i, map)

  def read(%{state: map}) do
    Map.new(map, fn {key, values} ->
      {val, _ts} = Enum.max_by(Map.keys(values.state), fn {_val, ts} -> ts end)
      {key, val}
    end)
  end
end
