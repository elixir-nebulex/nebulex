defmodule Nebulex.Event do
  @moduledoc """
  Nebulex cache event.
  """

  @typedoc "Type for a cache event"
  @type t() :: Nebulex.Event.CacheEntryEvent.t()

  @typedoc "Type for the listener and filter metadata"
  @type metadata() :: map()

  @typedoc "Type for an entry event listener"
  @type listener() :: (t() -> any())

  @typedoc "Type for an entry event filter"
  @type filter() :: (t() -> boolean())
end
