defmodule DeltaCrdt.DummyCausalCrdt do
  @moduledoc false
  alias DeltaCrdt.CausalContext

  defstruct causal_context: CausalContext.new(),
            state: nil

  def new(), do: %__MODULE__{}
end

defimpl DeltaCrdt.DotStore, for: DeltaCrdt.DummyCausalCrdt do
  def dots(_), do: []
end
