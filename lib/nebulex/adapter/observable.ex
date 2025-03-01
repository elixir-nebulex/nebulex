defmodule Nebulex.Adapter.Observable do
  @moduledoc """
  Specifies the adapter Observable API.

  Maintains a registry of listeners and invokes them to handle cache events.

  ## Default implementation

  Nebulex provides a default implementation for the `Nebulex.Adapter.Observable`
  behaviour, which uses a Telemetry handler to listen to cache command
  completion events, builds the corresponding cache entry event, and applies
  the provided filter and listener.

  Listeners should be implemented with care. In particular, it is important
  to consider their impact on performance and latency.

  Listeners:

    * are fired after the entry is mutated in the cache.
    * block the calling process until the listener returns since the listener is
      evaluated synchronously.

  > #### Function Captures {: .info}
  >
  > Due to how anonymous functions are implemented in the Erlang VM, it is best
  > to use function captures (`&Mod.fun/1`) as event listeners and filters
  > to achieve the best performance. In other words, avoid using literal
  > anonymous functions (`fn ... -> ... end`) or local function captures
  > (`&handle_event/1`) as event listeners and filters.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta() :: Nebulex.Adapter.adapter_meta()

  @typedoc "Proxy type to the cache options"
  @type opts() :: Nebulex.Cache.opts()

  @typedoc "Proxy type to a cache event listener"
  @type listener() :: Nebulex.Event.listener()

  @typedoc "Proxy type to a cache event filter"
  @type filter() :: Nebulex.Event.filter()

  @typedoc "Proxy type to a cache event metadata"
  @type metadata() :: Nebulex.Event.metadata()

  @doc """
  Register a cache event listener.

  Returns `:ok` if successful; `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.register_event_listener/2`.
  """
  @callback register_event_listener(adapter_meta(), listener(), filter(), metadata(), opts()) ::
              :ok | Nebulex.Cache.error_tuple()

  @doc """
  Un-register a cache event listener.

  Returns `:ok` if successful; `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.unregister_event_listener/2`.
  """
  @callback unregister_event_listener(adapter_meta(), id :: any(), opts()) ::
              :ok | Nebulex.Cache.error_tuple()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Observable

      alias Nebulex.Telemetry.CacheEntryHandler

      @impl true
      def register_event_listener(
            %{cache: cache} = adapter_meta,
            listener,
            filter,
            metadata,
            opts
          ) do
        opts
        |> Keyword.get(:id, listener)
        |> CacheEntryHandler.register(adapter_meta[:name] || cache, listener, filter, metadata)
      end

      @impl true
      def unregister_event_listener(%{cache: cache} = adapter_meta, id, _opts) do
        CacheEntryHandler.unregister(id, adapter_meta[:name] || cache)
      end
    end
  end
end
