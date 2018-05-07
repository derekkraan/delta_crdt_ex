defprotocol DeltaCrdt.JoinSemilattice do
  @moduledoc """
  A join-semilattice is a set with a partial order and a binary join operation that returns the least upper bound (LUB) of two elements. A join is designed to be commutative, associative, and idempotent.
  """

  @doc "generates a new bottom state"
  def new(s1)

  @doc "joins two states s1 and s2"
  def join(s1, s2)

  @doc "reads the current state"
  def read(s1)
end
