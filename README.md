# DeltaCrdt

[![Hex pm](http://img.shields.io/hexpm/v/delta_crdt.svg?style=flat)](https://hex.pm/packages/delta_crdt) [![CircleCI badge](https://circleci.com/gh/derekkraan/delta_crdt_ex.png?circle-token=:circle-token)](https://circleci.com/gh/derekkraan/delta_crdt_ex)

DeltaCrdt implements some Delta CRDTs in Elixir. There is an [introductory blog post]() and the official documentation on [hexdocs.pm](https://hexdocs.pm/delta_crdt) is also very good.

CRDTs currently offered include:
- Add Wins Last Write Wins Map
- Add Wins Set

Please open an issue or a pull request if you'd like to see any additional Delta CRDTs included.

The following papers have used to implement this library:
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
DeltaCrdt.add_neighbours(crdt1, [crdt2])

# show the initial value
DeltaCrdt.read(crdt1)
%{}

# add a key/value in crdt1
DeltaCrdt.mutate(crdt1, :add, ["CRDT", "is magic!"])

# read it after it has been replicated to crdt2
DeltaCrdt.read(crdt2)
%{"CRDT" => "is magic!"}
```

## Installation

The package can be installed by adding `delta_crdt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:delta_crdt, "~> 0.2.1"}
  ]
end
```
