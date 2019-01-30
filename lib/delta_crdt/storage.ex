defmodule DeltaCrdt.Storage do
  @type t :: module()

  @callback write(name :: term(), DeltaCrdt.CausalCrdt.storage_format()) :: :ok
  @callback read(name :: term()) :: DeltaCrdt.CausalCrdt.storage_format() | nil
end
