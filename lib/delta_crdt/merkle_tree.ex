defmodule MerkleTree do
  defstruct children: {nil, nil},
            hash: ""

  def from_map(map) do
    Enum.reduce(map, %__MODULE__{}, fn {key, val}, tree ->
      put_in_tree(tree, {key, val})
    end)
    |> calculate_hash()
  end

  def hash(thing) do
    <<Murmur.hash_x86_32(thing)::size(32)>>
  end

  def location(key) do
    hash(key)
  end

  def identical?(%{hash: hash}, %{hash: hash}), do: true
  def identical?(_, _), do: false

  def all_leaves(nil, _loc), do: []

  def all_leaves(%{children: {a, b}}, loc) do
    all_leaves(a, <<loc::bitstring, 0::1>>) ++ all_leaves(b, <<loc::bitstring, 1::1>>)
  end

  def all_leaves(%{children: %{} = values}, _loc), do: Map.keys(values)

  def all_leaves(%{children: :partial}, loc), do: [{:partial, loc}]

  def diff(tree1, tree2, loc \\ <<>>)

  def diff(nil, nil, _loc), do: []
  # def diff(tree, nil, _loc), do: diff(nil, tree)
  def diff(%{hash: hash}, %{hash: hash}, _loc), do: []

  def diff(nil, %{children: {_b1, _b2}} = tree, loc),
    do: all_leaves(tree, <<loc::bitstring, 0::1>>)

  def diff(%{children: {_b1, _b2}} = tree, nil, loc),
    do: all_leaves(tree, <<loc::bitstring, 1::1>>)

  def diff(nil, %{children: %{} = values}, _loc), do: Map.keys(values)

  def diff(%{children: {a1, a2}}, %{children: {b1, b2}}, loc) do
    diff(a1, b1, <<loc::bitstring, 0::1>>) ++ diff(a2, b2, <<loc::bitstring, 1::1>>)
  end

  def diff(%{children: :partial}, _, loc) do
    [{:partial, loc}]
  end

  def diff(_, %{children: :partial}, loc) do
    [{:partial, loc}]
  end

  def diff(%{children: v1 = %{}}, %{children: v2 = %{}}, _loc) do
    (Map.keys(v1) ++ Map.keys(v2)) |> Enum.uniq()
  end

  def prune_empty_nodes(%{children: {nil, nil}}), do: nil
  def prune_empty_nodes(tree), do: tree

  def calculate_hash(%{children: {first, second}} = tree) do
    first = init_empty_inner_node(first)
    second = init_empty_inner_node(second)
    %__MODULE__{tree | hash: hash(first.hash <> second.hash)}
  end

  def partial_tree(nil, _levels, _), do: nil

  def partial_tree(%{children: {a, _b}}, levels, <<0::1, rest_loc::bits>>),
    do: partial_tree(a, levels, rest_loc)

  def partial_tree(%{children: {_a, b}}, levels, <<1::1, rest_loc::bits>>),
    do: partial_tree(b, levels, rest_loc)

  def partial_tree(%{children: %{} = values} = tree, _levels, _loc) do
    tree
  end

  def partial_tree(tree, levels, <<>>), do: partial_tree(tree, levels)

  def partial_tree(nil, _levels), do: nil

  def partial_tree(tree, 0) do
    %{tree | children: :partial}
  end

  def partial_tree(tree, levels) do
    %{children: {a, b}} = tree
    %{tree | children: {partial_tree(a, levels - 1), partial_tree(b, levels - 1)}}
  end

  def remove_key(tree, key) do
    case remove_key(tree, location(key), key) do
      nil -> %__MODULE__{} |> calculate_hash()
      tree -> tree
    end
  end

  def remove_key(tree, <<0::size(1), rest_loc::bits>>, key) do
    %{children: {first, second}} = init_empty_inner_node(tree)
    new_first = remove_key(first, rest_loc, key)
    %__MODULE__{children: {new_first, second}} |> calculate_hash() |> prune_empty_nodes()
  end

  def remove_key(tree, <<1::size(1), rest_loc::bits>>, key) do
    %{children: {first, second}} = init_empty_inner_node(tree)
    new_second = remove_key(second, rest_loc, key)
    %__MODULE__{children: {first, new_second}} |> calculate_hash() |> prune_empty_nodes()
  end

  def remove_key(tree, <<>>, key) do
    %{children: %{} = values} = init_empty_leaf(tree)
    new_values = Map.delete(values, key)

    if Map.size(new_values) == 0 do
      nil
    else
      %__MODULE__{children: new_values, hash: hash(new_values)}
    end
  end

  def put_in_tree(tree, {key, value}) do
    put_in_tree(tree, location(key), {key, value})
  end

  defp put_in_tree(tree, <<0::size(1), rest_loc::bits>>, kv) do
    %{children: {first, second}} = init_empty_inner_node(tree)
    new_first = put_in_tree(first, rest_loc, kv)
    %__MODULE__{children: {new_first, second}} |> calculate_hash()
  end

  defp put_in_tree(tree, <<1::size(1), rest_loc::bits>>, kv) do
    %{children: {first, second}} = init_empty_inner_node(tree)
    new_second = put_in_tree(second, rest_loc, kv)
    %__MODULE__{children: {first, new_second}} |> calculate_hash()
  end

  defp put_in_tree(tree, <<>>, {key, value}) do
    %{children: values = %{}} = init_empty_leaf(tree)
    new_values = Map.put(values, key, hash(value))
    %__MODULE__{children: new_values, hash: hash(new_values)}
  end

  defp init_empty_leaf(%__MODULE__{} = tree), do: tree
  defp init_empty_leaf(nil), do: %__MODULE__{children: %{}}

  defp init_empty_inner_node(%__MODULE__{} = tree), do: tree
  defp init_empty_inner_node(nil), do: %__MODULE__{children: {nil, nil}}
end
