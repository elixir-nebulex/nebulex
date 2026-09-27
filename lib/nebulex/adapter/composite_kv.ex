defmodule Nebulex.Adapter.CompositeKV do
  @moduledoc """
  Specifies the adapter Composite KV API.

  Composite operations combine a read and a write on the same key in one
  call and receive a function as an argument. This behaviour covers
  `c:get_and_update/6`, `c:update/7`, `c:fetch_or_store/6`, and
  `c:get_or_store/6`.

  By default, Nebulex builds these operations on top of the
  `Nebulex.Adapter.KV` primitives (`fetch`, `put`, and `delete`), and the
  given function runs in the calling process, on the local node. This holds
  even when the adapter performs the underlying read and write commands on
  remote nodes.

  Because the read and the write are separate commands, the default
  implementation is **not atomic**:

    * For `c:get_and_update/6` and `c:update/7`, concurrent calls on the
      same key can overwrite each other's changes.

    * For `c:fetch_or_store/6` and `c:get_or_store/6`, concurrent cache
      misses on the same key can evaluate the function more than once, and
      the last write wins.

  If atomicity is required and the adapter supports transactions, wrap the
  call in `c:Nebulex.Cache.transaction/2` locking the key with the `:keys`
  option. The lock coordinates only writers that use transactions on the same
  keys; plain writes are not affected.

  This behaviour is required: `Nebulex.Cache` validates at compile time that
  the adapter implements it, alongside `Nebulex.Adapter` and
  `Nebulex.Adapter.KV`. Most adapters get it with
  `use Nebulex.Adapter.CompositeKV`, which provides the default implementation
  in this module. An adapter implements the callbacks itself to change where
  the function runs (e.g., on the node owning the key) or to provide different
  atomicity guarantees.

  ## Default implementation

  `use Nebulex.Adapter.CompositeKV` declares the behaviour and provides the
  default implementation for every callback. The callbacks are overridable,
  so an adapter can override only some of them:

      defmodule MyAdapter do
        @behaviour Nebulex.Adapter
        @behaviour Nebulex.Adapter.KV

        use Nebulex.Adapter.CompositeKV

        # Override `get_and_update/6` and `update/7`; the other callbacks
        # fall back to the default implementation.
        @impl true
        def get_and_update(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
          # Adapter-specific implementation ...
        end

        @impl true
        def update(adapter_meta, key, initial, fun, ttl, keep_ttl?, opts) do
          # Adapter-specific implementation ...
        end

        ...
      end

  ## Telemetry

  Each composite operation is a cache command itself: a Telemetry span with
  `command: :get_and_update`, `command: :update`, `command: :fetch_or_store`,
  or `command: :get_or_store` is emitted. The default implementation runs the
  primitive commands through `Nebulex.Adapter.run_command/4`, so each of them
  emits its own command span as well, and the cache entry events and stats
  built on those spans are still produced. The shared `:telemetry`,
  `:telemetry_event`, and `:telemetry_metadata` options apply to the composite
  command span and are forwarded to the primitive commands.

  > #### Overrides and cache entry events {: .warning}
  >
  > The built-in cache entry (`Nebulex.Event.CacheEntryEvent`) and stats
  > handlers are driven by the primitive command events, not by the composite
  > one. If an override bypasses those commands, or runs them under another
  > cache's metadata, those handlers will not account for the operation on
  > the original cache. Preserve equivalent events for the affected cache
  > when implementing an override.
  """

  import Nebulex.Utils, only: [wrap_error: 2]

  alias Nebulex.Adapter

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta() :: Nebulex.Adapter.adapter_meta()

  @doc """
  Gets the value for `key` and updates it using the given function.

  `fun` is called with the current cached value under `key` (or `nil` if
  `key` hasn't been cached) and must return a two-element tuple: the value to
  return as the current value, which may differ from the cached one, and the
  new value to store under `key`. `fun` may also return `:pop` to remove the
  entry and return the current value.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, {current_value, new_value}}` if successful;
  `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.get_and_update/3`.
  """
  @callback get_and_update(
              adapter_meta(),
              Nebulex.Cache.key(),
              Nebulex.Cache.get_and_update_fun(),
              Nebulex.Cache.ttl(),
              Nebulex.Cache.keep_ttl(),
              Nebulex.Cache.opts()
            ) :: Nebulex.Cache.ok_error_tuple({Nebulex.Cache.value(), Nebulex.Cache.value()})

  @doc """
  Updates the cached `key` with the given function.

  If `key` is present in the cache, `fun` is invoked with the current value
  and its result is stored under `key`. If `key` is not present, `initial`
  is stored under `key` and `fun` is not invoked.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, value}` with the stored value if successful;
  `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.update/4`.
  """
  @callback update(
              adapter_meta(),
              Nebulex.Cache.key(),
              initial :: Nebulex.Cache.value(),
              Nebulex.Cache.update_fun(),
              Nebulex.Cache.ttl(),
              Nebulex.Cache.keep_ttl(),
              Nebulex.Cache.opts()
            ) :: Nebulex.Cache.ok_error_tuple(Nebulex.Cache.value())

  @doc """
  Fetches the value for `key` or, on a cache miss, evaluates `fun` and
  stores its result.

  `fun` must return `{:ok, value}`, in which case `value` is stored under
  `key` and returned, or `{:error, reason}`, in which case nothing is
  stored and the error is returned.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, value}` if successful; `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.fetch_or_store/3`.
  """
  @callback fetch_or_store(
              adapter_meta(),
              Nebulex.Cache.key(),
              Nebulex.Cache.fetch_or_store_fun(),
              Nebulex.Cache.ttl(),
              Nebulex.Cache.keep_ttl(),
              Nebulex.Cache.opts()
            ) :: Nebulex.Cache.ok_error_tuple(Nebulex.Cache.value())

  @doc """
  Gets the value for `key` or, on a cache miss, evaluates `fun` and stores
  whatever it returns.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, value}` if successful; `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.get_or_store/3`.
  """
  @callback get_or_store(
              adapter_meta(),
              Nebulex.Cache.key(),
              Nebulex.Cache.get_or_store_fun(),
              Nebulex.Cache.ttl(),
              Nebulex.Cache.keep_ttl(),
              Nebulex.Cache.opts()
            ) :: Nebulex.Cache.ok_error_tuple(Nebulex.Cache.value())

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.CompositeKV

      @impl true
      defdelegate get_and_update(adapter_meta, key, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      @impl true
      defdelegate update(adapter_meta, key, initial, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      @impl true
      defdelegate fetch_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      @impl true
      defdelegate get_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      defoverridable get_and_update: 6, update: 7, fetch_or_store: 6, get_or_store: 6
    end
  end

  ## Default implementation

  @doc """
  Default implementation for `c:get_and_update/6`.
  """
  @spec get_and_update(
          adapter_meta(),
          Nebulex.Cache.key(),
          Nebulex.Cache.get_and_update_fun(),
          Nebulex.Cache.ttl(),
          Nebulex.Cache.keep_ttl(),
          Nebulex.Cache.opts()
        ) ::
          Nebulex.Cache.ok_error_tuple({Nebulex.Cache.value(), Nebulex.Cache.value()})
  def get_and_update(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
    with {:ok, entry} <- fetch_entry(adapter_meta, key, opts) do
      current = current_value(entry)

      eval_get_and_update_fun(fun.(current), entry, adapter_meta, key, ttl, keep_ttl?, opts)
    end
  end

  @doc """
  Default implementation for `c:update/7`.
  """
  @spec update(
          adapter_meta(),
          Nebulex.Cache.key(),
          Nebulex.Cache.value(),
          Nebulex.Cache.update_fun(),
          Nebulex.Cache.ttl(),
          Nebulex.Cache.keep_ttl(),
          Nebulex.Cache.opts()
        ) :: Nebulex.Cache.ok_error_tuple(Nebulex.Cache.value())
  def update(adapter_meta, key, initial, fun, ttl, keep_ttl?, opts) do
    with {:ok, value} <- eval_update_fun(adapter_meta, key, initial, fun, opts) do
      put(adapter_meta, key, value, ttl, keep_ttl?, opts)
    end
  end

  @doc """
  Default implementation for `c:fetch_or_store/6`.
  """
  @spec fetch_or_store(
          adapter_meta(),
          Nebulex.Cache.key(),
          Nebulex.Cache.fetch_or_store_fun(),
          Nebulex.Cache.ttl(),
          Nebulex.Cache.keep_ttl(),
          Nebulex.Cache.opts()
        ) :: Nebulex.Cache.ok_error_tuple(Nebulex.Cache.value())
  def fetch_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- run(adapter_meta, :fetch, [key], opts) do
      eval_fetch_or_store_fun(fun.(), adapter_meta, key, ttl, keep_ttl?, opts)
    end
  end

  @doc """
  Default implementation for `c:get_or_store/6`.
  """
  @spec get_or_store(
          adapter_meta(),
          Nebulex.Cache.key(),
          Nebulex.Cache.get_or_store_fun(),
          Nebulex.Cache.ttl(),
          Nebulex.Cache.keep_ttl(),
          Nebulex.Cache.opts()
        ) :: Nebulex.Cache.ok_error_tuple(Nebulex.Cache.value())
  def get_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- run(adapter_meta, :fetch, [key], opts) do
      put(adapter_meta, key, fun.(), ttl, keep_ttl?, opts)
    end
  end

  ## Private functions

  # The cached entry, as `{:hit, value}` or `:miss`. The distinction lets
  # `:pop` delete an entry holding `nil`.
  defp fetch_entry(adapter_meta, key, opts) do
    case run(adapter_meta, :fetch, [key], opts) do
      {:ok, value} -> {:ok, {:hit, value}}
      {:error, %Nebulex.KeyError{key: ^key}} -> {:ok, :miss}
      {:error, _} = error -> error
    end
  end

  defp current_value({:hit, value}), do: value
  defp current_value(:miss), do: nil

  defp eval_get_and_update_fun({get, update}, _entry, adapter_meta, key, ttl, keep_ttl?, opts) do
    with {:ok, _} <- run(adapter_meta, :put, [key, update, :put, ttl, keep_ttl?], opts) do
      {:ok, {get, update}}
    end
  end

  defp eval_get_and_update_fun(:pop, :miss, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    {:ok, {nil, nil}}
  end

  defp eval_get_and_update_fun(:pop, {:hit, current}, adapter_meta, key, _ttl, _keep_ttl?, opts) do
    with :ok <- run(adapter_meta, :delete, [key], opts) do
      {:ok, {current, nil}}
    end
  end

  defp eval_get_and_update_fun(other, _entry, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    raise ArgumentError,
          "the given function must return a two-element tuple or :pop," <>
            " got: #{inspect(other)}"
  end

  defp eval_update_fun(adapter_meta, key, initial, fun, opts) do
    case run(adapter_meta, :fetch, [key], opts) do
      {:ok, value} -> {:ok, fun.(value)}
      {:error, %Nebulex.KeyError{key: ^key}} -> {:ok, initial}
      {:error, _} = error -> error
    end
  end

  defp eval_fetch_or_store_fun({:ok, value}, adapter_meta, key, ttl, keep_ttl?, opts) do
    put(adapter_meta, key, value, ttl, keep_ttl?, opts)
  end

  defp eval_fetch_or_store_fun({:error, reason}, _adapter_meta, key, _ttl, _keep_ttl?, _opts) do
    wrap_error Nebulex.Error, reason: reason, command: :fetch_or_store, key: key
  end

  defp eval_fetch_or_store_fun(other, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    raise "the supplied lambda function must return {:ok, value} " <>
            "or {:error, reason}, got: #{inspect(other)}"
  end

  defp put(adapter_meta, key, value, ttl, keep_ttl?, opts) do
    with {:ok, _} <- run(adapter_meta, :put, [key, value, :put, ttl, keep_ttl?], opts) do
      {:ok, value}
    end
  end

  defp run(adapter_meta, command, args, opts) do
    adapter_meta
    |> Adapter.run_command(command, args, opts)
    |> Adapter.handle_command_response()
  end
end
