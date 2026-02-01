defmodule Nebulex.Telemetry.CacheEntryHandler do
  @moduledoc """
  A Telemetry handler listens to cache command completion events, builds the
  corresponding cache entry event, and applies the provided filter and listener.
  """

  import Nebulex.Utils, only: [wrap_error: 2]

  alias Nebulex.Adapter
  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Telemetry

  ## API

  @doc """
  Registers a new Telemetry handler for listening and handling cache entry
  events.
  """
  @spec register(
          Adapter.adapter_meta(),
          Nebulex.Event.listener(),
          Nebulex.Event.filter(),
          Nebulex.Event.metadata(),
          keyword()
        ) :: :ok | Nebulex.Error.t()
  def register(
        %{name: name, pid: pid, telemetry_prefix: telemetry_prefix},
        listener,
        filter,
        meta,
        opts
      ) do
    cache_name = name || pid
    id = Keyword.get(opts, :id, listener)
    handler_id = {name, id}

    with {:error, :already_exists} <-
           Telemetry.attach_many(
             handler_id,
             [telemetry_prefix ++ [:command, :stop]],
             &__MODULE__.handle_event/4,
             %{name: cache_name, pid: pid, listener: listener, filter: filter, meta: meta}
           ) do
      wrap_error Nebulex.Error,
        reason: :event_listener_already_exists,
        cache: cache_name,
        id: handler_id,
        listener: listener,
        filter: filter
    end
  end

  @doc """
  Un-registers a Telemetry handler that listens and handles cache entry events.
  """
  def unregister(%{name: name, pid: pid}, id, _opts) do
    _ignore = Telemetry.detach({name || pid, id})

    :ok
  end

  ## Handler

  @doc false
  def handle_event(event, measurements, metadata, config)

  def handle_event(
        _event,
        _measurements,
        %{
          command: command,
          args: args,
          result: result,
          adapter_meta: %{cache: cache, pid: pid}
        },
        %{pid: pid, name: name, meta: meta} = config
      ) do
    do_handle(command, args, result, [cache: cache, name: name, pid: pid, metadata: meta], config)
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ignore
  end

  ## Private functions

  defp do_handle(:put, [key, _, :replace | _], {:ok, true}, event_attrs, config) do
    [
      target: {:key, key},
      command: :replace
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.updated()
    |> evaluate(config)
  end

  defp do_handle(:put, [key, _, on_write | _], {:ok, true}, event_attrs, config) do
    [
      target: {:key, key},
      command: on_write
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.inserted()
    |> evaluate(config)
  end

  defp do_handle(:put_all, [entries, :put_new | _], {:ok, true}, event_attrs, config) do
    [
      target: {:in, Enum.map(entries, &elem(&1, 0))},
      command: :put_new_all
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.inserted()
    |> evaluate(config)
  end

  defp do_handle(:put_all, [entries | _], {:ok, true}, event_attrs, config) do
    [
      target: {:in, Enum.map(entries, &elem(&1, 0))},
      command: :put_all
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.inserted()
    |> evaluate(config)
  end

  defp do_handle(
         :update_counter,
         [key, amount, default, _, _ | _],
         {:ok, result},
         event_attrs,
         config
       ) do
    {command, offset} = if amount >= 0, do: {:incr, -1}, else: {:decr, 1}
    type = if result + amount * offset === default, do: :inserted, else: :updated

    [
      target: {:key, key},
      command: command,
      type: type
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.new()
    |> evaluate(config)
  end

  defp do_handle(command, [key | _], {:ok, true}, event_attrs, config)
       when command in [:expire, :touch] do
    [
      target: {:key, key},
      command: command
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.updated()
    |> evaluate(config)
  end

  defp do_handle(:delete, [key | _], :ok, event_attrs, config) do
    [
      target: {:key, key},
      command: :delete
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.deleted()
    |> evaluate(config)
  end

  defp do_handle(:take, [key | _], {:ok, _}, event_attrs, config) do
    [
      target: {:key, key},
      command: :take
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.deleted()
    |> evaluate(config)
  end

  defp do_handle(
         :execute,
         [%{op: :delete_all, query: query} | _],
         {:ok, count},
         event_attrs,
         config
       )
       when count > 0 do
    [
      target: query,
      command: :delete_all
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.deleted()
    |> evaluate(config)
  end

  defp do_handle(
         command,
         [key | _],
         {:error, %Nebulex.KeyError{reason: :expired}},
         event_attrs,
         config
       )
       when command in [:fetch, :take, :ttl, :has_key?] do
    [
      target: {:key, key},
      command: command
    ]
    |> Kernel.++(event_attrs)
    |> CacheEntryEvent.expired()
    |> evaluate(config)
  end

  defp do_handle(_command, _args, _result, _event_attrs, _config) do
    :noop
  end

  defp evaluate(event, %{listener: listener, filter: filter}) do
    case filter.(event) do
      true -> listener.(event)
      false -> :noop
    end
  rescue
    original_ex ->
      raise Nebulex.Error,
        reason: :event_listener_error,
        original: original_ex,
        event: event,
        listener: listener
  catch
    :exit, reason ->
      raise Nebulex.Error,
        reason: :event_listener_error,
        original: {:exit, reason},
        event: event,
        listener: listener
  end
end
