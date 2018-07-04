defprotocol DeltaCrdt.SemiLattice do
  @fallback_to_any true

  def join(semilattice1, semilattice2)
  def bottom?(semilattice)
  def minimum_delta(state, delta)
  def compress(semilattice)
end

defimpl DeltaCrdt.SemiLattice, for: Any do
  def join(%{state: :bottom} = s1, %{state: :bottom} = s2) do
    %{s1 | causal_context: DeltaCrdt.CausalContext.join(s1.causal_context, s2.causal_context)}
  end

  def join(s1, %{__struct__: struct} = s2) do
    DeltaCrdt.SemiLattice.join(Map.merge(struct.new(), s1), s2)
  end

  def bottom?(%{state: :bottom}), do: true
  def bottom?(_), do: false

  def compress(s), do: s
end
