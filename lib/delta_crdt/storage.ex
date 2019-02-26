defmodule DeltaCrdt.Storage do
  @moduledoc """
  This behaviour can be used to enable persistence of the CRDT.

  This can be helpful in the event of crashes.

  To use, implement this behaviour in a module, and pass it to your CRDT with the `storage_module` option.
  """

  @type t :: module()

  @opaque storage_format ::
            {node_id :: term(), sequence_number :: integer(), crdt_state :: term()}

  @callback write(name :: term(), storage_format()) :: :ok
  @callback read(name :: term()) :: storage_format() | nil
end
