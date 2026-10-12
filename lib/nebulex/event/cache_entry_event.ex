defmodule Nebulex.Event.CacheEntryEvent do
  @moduledoc """
  A cache entry event.
  """

  @typedoc """
  Event type.

    * `:deleted` - Emitted after an entry is deleted, or after a batch
      delete. The commands `delete`, `take`, and `delete_all` emit it. Note
      that `delete` emits it even when the key did not exist, since there is
      no way to know.
    * `:expired` - Emitted when a read finds the entry expired. The commands
      `fetch`, `take`, `ttl`, and `has_key?` emit it.
    * `:inserted` - Emitted after an entry is inserted, or after a batch
      insert. The commands `put`, `put_new`, `put_all`, and `put_new_all`
      emit it, as do `incr` and `decr` when they create the counter. Note
      that for `put` and `put_all` there is no way to know whether the entry
      existed before.
    * `:updated` - Emitted when an existing entry changes. The commands
      `replace`, `expire`, and `touch` emit it, as do `incr` and `decr` when
      the counter already exists.

  """
  @type type() :: :deleted | :expired | :inserted | :updated

  @typedoc """
  Type for the event target.

  The event can target a single key, a list of keys, or a query.

    * A single key: `{:key, key}`. A command writing or deleting a single key
      will use this target. E.g., `put`, `put_new`, `replace`, `delete`, etc.
    * A list of keys: `{:in, [key1, key2, ...]}`. A command writing or deleting
      multiple keys will use this target. E.g., `put_all`, `put_new_all`, and
      `delete_all`.
    * A query: `{:q, query}`. A command deleting entries matching a query will
      use this target. E.g., `delete_all`.

  """
  @type target() :: {:key, key :: any()} | {:in, [key :: any()]} | {:q, query :: any()}

  @typedoc """
  Type for a cache entry event.

  The event will have the following keys:

    * `:cache` - The defined cache module.
    * `:name` - The cache name, or the cache PID when the cache was started
      without a name.
    * `:pid` - The cache PID.
    * `:type` - The event type.
    * `:target` - The event target: a key, a list of keys, or a query.
      See `t:target/0`.
    * `:command` - The cache command that emitted the event.
    * `:metadata` - The metadata given when the listener was registered.
      It also includes `:extra_metadata` with the per-command metadata
      passed through the `:telemetry_metadata` runtime option.

  """
  @type t() :: %__MODULE__{
          cache: Nebulex.Cache.t(),
          name: atom() | pid(),
          pid: pid() | nil,
          type: type(),
          target: target(),
          command: atom(),
          metadata: Nebulex.Event.metadata()
        }

  # Event structure
  @enforce_keys [:cache, :pid, :type, :target, :command]
  defstruct [:cache, :name, :pid, :type, :target, :command, metadata: %{}]

  # Supported event types
  @event_types ~w(deleted expired inserted updated)a

  ## API

  # Inline common instructions
  @compile inline: [__types__: 0, new: 1]

  @doc """
  Returns the event types.

  ## Example

      iex> Nebulex.Event.CacheEntryEvent.__types__()
      [:deleted, :expired, :inserted, :updated]

  """
  @spec __types__() :: [atom()]
  def __types__, do: @event_types

  @doc """
  Creates a new event.

  ## Example

      iex> Nebulex.Event.CacheEntryEvent.new(
      ...>   cache: MyApp.Cache,
      ...>   pid: self(),
      ...>   target: {:key, "foo"},
      ...>   command: :put,
      ...>   type: :inserted
      ...> )
      %Nebulex.Event.CacheEntryEvent{
        cache: MyApp.Cache,
        command: :put,
        name: nil,
        pid: self(),
        type: :inserted,
        metadata: %{},
        target: {:key, "foo"}
      }

  """
  @spec new(Enumerable.t()) :: t()
  def new(enum), do: struct!(__MODULE__, enum)

  for type <- @event_types do
    @doc """
    Creates a new `#{type}` event.
    """
    @spec unquote(type)(Enumerable.t()) :: t()
    def unquote(type)(enum) do
      enum
      |> Enum.into(%{})
      |> Map.put(:type, unquote(type))
      |> new()
    end
  end
end
