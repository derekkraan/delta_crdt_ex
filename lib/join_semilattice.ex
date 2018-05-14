defprotocol DeltaCrdt.JoinSemilattice do
  @fallback_to_any true

  @moduledoc """
  A join-semilattice is a set with a partial order and a binary join operation that returns the least upper bound (LUB) of two elements. A join is designed to be commutative, associative, and idempotent.
  """

  @doc "joins two states s1 and s2"
  def join(s1, s2)

  @doc """
  is the state at "bottom" (ie, empty)?
  """
  def bottom?(s1)
end

defimpl DeltaCrdt.JoinSemilattice, for: Any do
  def join(s1, :bottom), do: s1
  def join(:bottom, s1), do: s1

  def join(s1, s2) do
    new_state = DeltaCrdt.JoinSemilattice.join(s1.state, s2.state)
    %{s1 | state: new_state}
  end

  def bottom?(:bottom), do: true
  def bottom?(s1), do: DeltaCrdt.JoinSemilattice.bottom?(s1.state)
end
