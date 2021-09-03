# DeltaCrdt

[![Hex pm](http://img.shields.io/hexpm/v/delta_crdt.svg?style=flat)](https://hex.pm/packages/delta_crdt) [![CircleCI badge](https://circleci.com/gh/derekkraan/delta_crdt_ex.png?circle-token=:circle-token)](https://circleci.com/gh/derekkraan/delta_crdt_ex)

DeltaCrdt implements a key/value store using concepts from Delta CRDTs, and relies on [`MerkleMap`](https://github.com/derekkraan/merkle_map) for efficient synchronization.

There is a (slightly out of date) [introductory blog post](https://moosecode.nl/blog/how_deltacrdt_can_help_write_distributed_elixir_applications) and the (very much up to date) official documentation on [hexdocs.pm](https://hexdocs.pm/delta_crdt) is also very good.

The following papers have been used to implement this library:
- [`Delta State Replicated Data Types – Almeida et al. 2016`](https://arxiv.org/pdf/1603.01529.pdf)
- [`Efficient Synchronization of State-based CRDTs – Enes et al. 2018`](https://arxiv.org/pdf/1803.02750.pdf)

## Usage

Documentation can be found on [hexdocs.pm](https://hexdocs.pm/delta_crdt).

Here's a short example to illustrate adding an entry to a map:

```elixir
# start 2 Delta CRDTs
{:ok, crdt1} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)
{:ok, crdt2} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

# make them aware of each other
DeltaCrdt.set_neighbours(crdt1, [crdt2])

# show the initial value
DeltaCrdt.read(crdt1)
%{}

# add a key/value in crdt1
DeltaCrdt.put(crdt1, "CRDT", "is magic!")
DeltaCrdt.put(crdt1, "magic", "is awesome!")

# read it after it has been replicated to crdt2
DeltaCrdt.read(crdt2)
%{"CRDT" => "is magic!", "magic" => "is awesome!"}

# get only a subset of keys
DeltaCrdt.take(crdt2, ["magic"])
%{"magic" => "is awesome!"}

# get one value
DeltaCrdt.get(crdt2, "magic")
"is awesome!"

# Other map-like functions are available, see the documentation for details.
```

⚠️ **Use atoms carefully** : Any atom contained in a key or value will be replicated across all nodes, and will never be garbage collected by the BEAM.

## Telemetry metrics

DeltaCrdt publishes the metric `[:delta_crdt, :sync, :done]`.

## Installation

The package can be installed by adding `delta_crdt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:delta_crdt, "~> 0.6.3"}
  ]
end
```
