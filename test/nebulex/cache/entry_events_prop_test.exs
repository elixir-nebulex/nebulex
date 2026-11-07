defmodule Nebulex.Cache.EntryEventsPropTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Nebulex.CacheCase, only: [setup_with_cache: 1]

  alias Nebulex.CacheModel

  ## Internals

  defmodule Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  ## Tests

  describe "entry events" do
    setup_with_cache Cache

    property "any command sequence emits the events the map model expects" do
      :ok = Cache.register_event_listener!(&__MODULE__.listener/1, id: __MODULE__)

      try do
        check all pool <- CacheModel.key_pool(),
                  commands <- CacheModel.commands(pool, monotonic_counters: true) do
          {:ok, _} = Cache.delete_all()
          _ = flush_events()

          commands
          |> Enum.with_index(1)
          |> Enum.reduce(%{}, fn {command, index}, model ->
            expected = expected_events(model, command)
            {result, model} = CacheModel.step(model, command)

            assert CacheModel.exec(Cache, command) == result
            assert {index, command, flush_events()} == {index, command, expected}

            model
          end)
        end
      after
        :ok = Cache.unregister_event_listener!(__MODULE__)
      end
    end
  end

  ## Listener

  def listener(event) do
    send(self(), {:event, {event.type, normalize_target(event.target), event.command}})
  end

  defp normalize_target({:in, keys}), do: {:in, Enum.sort(keys)}
  defp normalize_target(target), do: target

  defp flush_events(acc \\ []) do
    receive do
      {:event, event} -> flush_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  ## Expected events

  # The events a command must emit, given the model before the command. They
  # follow the `t:Nebulex.Event.CacheEntryEvent.type/0` docs: `put` and
  # `put_all` always emit `:inserted` and `delete` always emits `:deleted`,
  # since there is no way to know whether the entry existed before.
  defp expected_events(model, command)

  defp expected_events(_model, {:put, key, _}) do
    [{:inserted, {:key, key}, :put}]
  end

  defp expected_events(model, {:put_new, key, _}) do
    if Map.has_key?(model, key), do: [], else: [{:inserted, {:key, key}, :put_new}]
  end

  defp expected_events(model, {:replace, key, _}) do
    if Map.has_key?(model, key), do: [{:updated, {:key, key}, :replace}], else: []
  end

  defp expected_events(_model, {:put_all, entries}) when map_size(entries) == 0 do
    []
  end

  defp expected_events(_model, {:put_all, entries}) do
    [{:inserted, {:in, Enum.sort(Map.keys(entries))}, :put_all}]
  end

  defp expected_events(model, {:put_new_all, entries}) do
    if map_size(entries) == 0 or Enum.any?(Map.keys(entries), &Map.has_key?(model, &1)) do
      []
    else
      [{:inserted, {:in, Enum.sort(Map.keys(entries))}, :put_new_all}]
    end
  end

  defp expected_events(_model, {:delete, key}) do
    [{:deleted, {:key, key}, :delete}]
  end

  defp expected_events(model, {:take, key}) do
    if Map.has_key?(model, key), do: [{:deleted, {:key, key}, :take}], else: []
  end

  defp expected_events(model, {:incr, key, amount, _default}) do
    [counter_event(model, key, amount)]
  end

  defp expected_events(model, {:decr, key, amount, _default}) do
    [counter_event(model, key, -amount)]
  end

  defp expected_events(model, {:delete_all, keys}) do
    if Enum.any?(keys, &Map.has_key?(model, &1)) do
      [{:deleted, {:in, Enum.sort(keys)}, :delete_all}]
    else
      []
    end
  end

  defp expected_events(_model, _read) do
    []
  end

  # A counter command emits `:inserted` when it creates the counter and
  # `:updated` otherwise. The command name follows the sign of the change,
  # so `decr` with a negative amount is reported as `:incr`.
  defp counter_event(model, key, change) do
    type = if Map.has_key?(model, key), do: :updated, else: :inserted
    command = if change >= 0, do: :incr, else: :decr

    {type, {:key, key}, command}
  end
end
