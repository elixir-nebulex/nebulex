defmodule Nebulex.Cache.InfoStatsPropTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Nebulex.CacheCase, only: [setup_with_cache: 2]

  alias Nebulex.CacheModel

  ## Internals

  defmodule Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  # All counters at zero.
  @zero_stats %{
    hits: 0,
    misses: 0,
    writes: 0,
    updates: 0,
    deletions: 0,
    evictions: 0,
    expirations: 0
  }

  ## Tests

  describe "stats" do
    setup_with_cache Cache, stats: true

    property "any command sequence updates the counters the map model expects" do
      check all pool <- CacheModel.key_pool(),
                commands <- CacheModel.commands(pool, monotonic_counters: true) do
        {:ok, _} = Cache.delete_all()
        initial = Cache.info!(:stats)

        commands
        |> Enum.with_index(1)
        |> Enum.reduce({%{}, @zero_stats}, fn {command, index}, {model, stats} ->
          stats = Map.merge(stats, expected_stats(model, command), fn _, a, b -> a + b end)
          {result, model} = CacheModel.step(model, command)

          assert CacheModel.exec(Cache, command) == result
          assert {index, command, stats_since(initial)} == {index, command, stats}

          {model, stats}
        end)
      end
    end
  end

  defp stats_since(initial) do
    Map.new(Cache.info!(:stats), fn {stat, count} -> {stat, count - initial[stat]} end)
  end

  ## Expected stats

  # The counters a command must increment, given the model before the command.
  # They follow the `Nebulex.Adapters.Common.Info.Stats` docs. Two cases encode
  # current behaviour that the docs don't state: `has_key?` counts as a hit
  # even when it returns `{:ok, false}`, and `delete` counts as a deletion even
  # when the key is missing.
  defp expected_stats(model, command)

  defp expected_stats(_model, {:put, _, _}) do
    %{writes: 1}
  end

  defp expected_stats(model, {:put_new, key, _}) do
    if Map.has_key?(model, key), do: %{}, else: %{writes: 1}
  end

  defp expected_stats(model, {:replace, key, _}) do
    if Map.has_key?(model, key), do: %{updates: 1}, else: %{}
  end

  defp expected_stats(_model, {:put_all, entries}) do
    %{writes: map_size(entries)}
  end

  defp expected_stats(model, {:put_new_all, entries}) do
    if Enum.any?(Map.keys(entries), &Map.has_key?(model, &1)) do
      %{}
    else
      %{writes: map_size(entries)}
    end
  end

  defp expected_stats(model, {:fetch, key}) do
    if Map.has_key?(model, key), do: %{hits: 1}, else: %{misses: 1}
  end

  defp expected_stats(model, {:take, key}) do
    if Map.has_key?(model, key), do: %{hits: 1, deletions: 1}, else: %{misses: 1}
  end

  defp expected_stats(model, {:get, key, _default}) do
    if Map.has_key?(model, key), do: %{hits: 1}, else: %{misses: 1}
  end

  defp expected_stats(_model, {:has_key?, _key}) do
    %{hits: 1}
  end

  defp expected_stats(_model, {:delete, _key}) do
    %{deletions: 1}
  end

  defp expected_stats(model, {counter, key, _amount, _default}) when counter in [:incr, :decr] do
    if Map.has_key?(model, key), do: %{updates: 1}, else: %{writes: 1}
  end

  defp expected_stats(model, {:get_all, keys}) do
    hits = Enum.count(keys, &Map.has_key?(model, &1))

    %{hits: hits, misses: length(keys) - hits}
  end

  defp expected_stats(_model, {:count_all}) do
    %{}
  end

  defp expected_stats(model, {:delete_all, keys}) do
    %{deletions: Enum.count(keys, &Map.has_key?(model, &1))}
  end
end
