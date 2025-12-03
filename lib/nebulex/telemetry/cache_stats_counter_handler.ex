defmodule Nebulex.Telemetry.CacheStatsCounterHandler do
  @moduledoc """
  Telemetry handler for aggregating cache stats; it relies on the default
  `Nebulex.Adapters.Common.Info` implementation based on Erlang counters.
  See `Nebulex.Adapters.Common.Info.Stats`.
  """

  alias Nebulex.Adapters.Common.Info.Stats
  alias Nebulex.Telemetry

  ## API

  @doc """
  Attach a new Telemetry handler for handling cache stats.
  """
  @spec attach(counter :: Stats.counter(), telemetry_prefix :: [atom()]) ::
          :ok | {:error, :already_exists}
  def attach(counter_ref, telemetry_prefix) do
    Telemetry.attach_many(
      counter_ref,
      [telemetry_prefix ++ [:command, :stop]],
      &__MODULE__.handle_event/4,
      counter_ref
    )
  end

  ## Handler

  @doc false
  def handle_event(
        _event,
        _measurements,
        %{adapter_meta: %{stats_counter: ref}} = metadata,
        ref
      )
      when not is_nil(ref) do
    update_stats(metadata)
  end

  # coveralls-ignore-start

  def handle_event(_event, _measurements, _metadata, _ref) do
    :ok
  end

  # coveralls-ignore-stop

  defp update_stats(%{
         command: action,
         result: {:error, %Nebulex.KeyError{reason: :expired}},
         adapter_meta: %{stats_counter: ref}
       })
       when action in [:fetch, :take, :ttl, :has_key?] do
    :ok = Stats.incr(ref, [:misses, :evictions, :expirations, :deletions])
  end

  defp update_stats(%{
         command: action,
         result: {:error, %Nebulex.KeyError{reason: :not_found}},
         adapter_meta: %{stats_counter: ref}
       })
       when action in [:fetch, :take, :ttl, :has_key?] do
    :ok = Stats.incr(ref, :misses)
  end

  defp update_stats(%{
         command: action,
         result: {:ok, _},
         adapter_meta: %{stats_counter: ref}
       })
       when action in [:fetch, :ttl, :has_key?] do
    :ok = Stats.incr(ref, :hits)
  end

  defp update_stats(%{
         command: :take,
         result: {:ok, _},
         adapter_meta: %{stats_counter: ref}
       }) do
    :ok = Stats.incr(ref, [:hits, :deletions])
  end

  defp update_stats(%{
         command: :put,
         args: [_, _, :replace, _, _, _],
         result: {:ok, true},
         adapter_meta: %{stats_counter: ref}
       }) do
    :ok = Stats.incr(ref, :updates)
  end

  defp update_stats(%{
         command: :put,
         result: {:ok, true},
         adapter_meta: %{stats_counter: ref}
       }) do
    :ok = Stats.incr(ref, :writes)
  end

  defp update_stats(%{
         command: :put_all,
         result: {:ok, true},
         args: [entries | _],
         adapter_meta: %{stats_counter: ref}
       }) do
    :ok = Stats.incr(ref, :writes, Enum.count(entries))
  end

  defp update_stats(%{
         command: :delete,
         result: :ok,
         adapter_meta: %{stats_counter: ref}
       }) do
    :ok = Stats.incr(ref, :deletions)
  end

  defp update_stats(%{
         command: :execute,
         args: [%{op: :get_all, query: {:in, keys}} | _],
         result: {:ok, list},
         adapter_meta: %{stats_counter: ref}
       }) do
    len = Enum.count(list)

    :ok = Stats.incr(ref, :hits, len)
    :ok = Stats.incr(ref, :misses, Enum.count(keys) - len)
  end

  defp update_stats(%{
         command: :execute,
         args: [%{op: :delete_all} | _],
         result: {:ok, result},
         adapter_meta: %{stats_counter: ref}
       }) do
    :ok = Stats.incr(ref, :deletions, result)
  end

  defp update_stats(%{
         command: action,
         result: {:ok, true},
         adapter_meta: %{stats_counter: ref}
       })
       when action in [:expire, :touch] do
    :ok = Stats.incr(ref, :updates)
  end

  defp update_stats(%{
         command: :update_counter,
         args: [_, amount, default, _, _ | _],
         result: {:ok, result},
         adapter_meta: %{stats_counter: ref}
       }) do
    offset = if amount >= 0, do: -1, else: 1

    if result + amount * offset === default do
      :ok = Stats.incr(ref, :writes)
    else
      :ok = Stats.incr(ref, :updates)
    end
  end

  defp update_stats(_) do
    :ok
  end
end
