defmodule Nebulex.Event.CacheEntryEvent do
  @moduledoc """
  A cache entry event.
  """

  @typedoc """
  Event type.

    * `:deleted` - Invoked if a cache entry is deleted, or if a batch call
      is made, after the entries are deleted. The commands `delete` and
      `delete_all` triggers this event.
    * `:expired` - Invoked if a cache entry or entries are evicted due to
      expiration.
    * `:inserted` - Invoked after a cache entry is inserted, or if a batch call
      is made after the entries are inserted. The commands triggering this event
      are: `put`, `put_new`, `put_all`, and `put_new_all`. Beware, for  `put`
      and `put_all` commands, there is no way to know if the entry existed
      before the operation.
    * `:updated` - Invoked if an existing cache entry is updated via `replace`
      command.

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
    * `:name` - The cache name (for dynamic caches).
    * `:pid` - The cache PID.
    * `:type` - The event type.
    * `:target` - The event target. It could be a key or a query
      (in case of `delete_all`).
    * `:command` - The cache command triggering the event.
    * `:metadata` - The event metadata is provided when the listener is
      registered.

  """
  @type t() :: %__MODULE__{
          cache: Nebulex.Cache.t(),
          name: atom() | nil,
          pid: pid() | nil,
          type: type(),
          target: target(),
          command: atom(),
          metadata: Nebulex.Event.metadata()
        }

  # Event structure
  @enforce_keys [:cache, :pid, :type, :target, :command]
  defstruct [:cache, :name, :pid, :type, :target, :command, metadata: []]

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
        metadata: [],
        target: {:key, "foo"}
      }

  """
  @spec new(Enumerable.t()) :: t()
  def new(enum), do: struct!(__MODULE__, enum)

  for type <- @event_types do
    @doc """
    Creates a new "**#{type}**" event.
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
