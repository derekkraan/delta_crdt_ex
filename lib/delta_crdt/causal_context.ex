defmodule DeltaCrdt.CausalContext do
  defstruct dots: MapSet.new(),
            maxima: %{}

  def new(dots \\ [])
  def new(%__MODULE__{} = cc), do: cc
  def new([]), do: %__MODULE__{}

  def new(dots) do
    maxima =
      dots
      |> Enum.reduce(%{}, fn {i, x}, maxima ->
        Map.update(maxima, i, x, fn y -> Enum.max([x, y]) end)
      end)

    %__MODULE__{
      dots: MapSet.new(dots),
      maxima: maxima
    }
  end

  def next(%__MODULE__{} = cc, i) do
    new_maxima = Map.update(cc.maxima, i, 0, fn x -> x + 1 end)
    next_dot = {i, Map.get(new_maxima, i)}
    new_dots = MapSet.put(cc.dots, next_dot)

    {next_dot, %{cc | dots: new_dots, maxima: new_maxima}}
  end

  def dots(%__MODULE__{dots: dots}), do: dots

  def join(cc1, cc2) do
    new_dots = MapSet.union(cc1.dots, cc2.dots)

    new_maxima =
      Enum.reduce(cc1.maxima, cc2.maxima, fn {i, x}, maxima ->
        Map.update(maxima, i, x, fn y -> Enum.max([x, y]) end)
      end)

    %__MODULE__{dots: new_dots, maxima: new_maxima}
  end

  def compress(%__MODULE__{} = cc) do
    %{cc | dots: MapSet.new(cc.maxima)}
  end
end
