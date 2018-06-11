# DeltaCrdt

DeltaCrdt implements some Delta CRDTs in Elixir.

CRDTs currently offered include:
- Add Wins Last Write Wins Map
- Add Wins Set
- Observed Remove Map

Please open an issue or a pull request if you'd like to see any additional Delta CRDTs included.

The following papers have been partially implemented in this library:
- [`Delta State Replicated Data Types – Almeida et al. 2016`](https://arxiv.org/pdf/1603.01529.pdf)
- [`Efficient Synchronization of State-based CRDTs – Enes et al. 2018`](https://arxiv.org/pdf/1803.02750.pdf)

## TODOs

- implement join decomposition to further reduce back-propagation.

## Installation

The package can be installed by adding `delta_crdt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:delta_crdt, "~> 0.1.2"}
  ]
end
```

Documentation can be found on [hexdocs.pm](https://hexdocs.pm/delta_crdt).
