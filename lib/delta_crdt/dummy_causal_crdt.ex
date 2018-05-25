defmodule DeltaCrdt.DummyCausalCrdt do
  alias DeltaCrdt.CausalContext

  defstruct causal_context: CausalContext.new(),
            state: nil

  def new(), do: %__MODULE__{}
end
