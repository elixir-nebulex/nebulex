defmodule Nebulex.CacheModel do
  @moduledoc false

  # A model of the KV and Queryable contract for model-based property tests.
  #
  # The model is a plain map. `step/2` gives the result a command must return
  # and the model after it, written from the `Nebulex.Cache` callback docs.
  # It must never be derived from an adapter: if it disagrees with the docs,
  # fix the docs or the model deliberately.

  import ExUnit.Assertions
  import StreamData

  @typedoc "A command, run against both the cache and the model"
  @type command() :: tuple()

  @typedoc "The model: the entries the cache must hold"
  @type t() :: %{optional(any()) => any()}

  ## Generators

  @doc false
  @spec key_pool() :: StreamData.t([any()])
  def key_pool do
    uniq_list_of(term(), min_length: 4, max_length: 9)
  end

  # Options:
  #
  #   * `:monotonic_counters` - When `true`, every counter command in a
  #     sequence uses the same `:default` and moves the value in the same
  #     direction, so an existing counter never holds the default. Telemetry
  #     can't tell such a counter from a new one (see `CacheEntryEvent`).
  #
  @doc false
  @spec commands([any()], keyword()) :: StreamData.t([command()])
  def commands(pool, opts \\ []) do
    {counters, keys} = Enum.split(pool, 2)

    if Keyword.get(opts, :monotonic_counters, false) do
      bind(tuple({member_of([1, -1]), integer()}), fn {sign, default} ->
        amount = map(positive_integer(), &(&1 * sign))

        list_of(command(keys, counters, amount, constant(default)), max_length: 30)
      end)
    else
      list_of(command(keys, counters, integer(), integer()), max_length: 30)
    end
  end

  # Keys collide often because they come from a small pool. Counter commands
  # only touch the counter keys, and other writes never do, so `incr` never
  # lands on a value that is not an integer. Reads and deletes use any key.
  defp command(keys, counters, amount, default) do
    key = member_of(keys)
    any_key = member_of(keys ++ counters)
    counter = member_of(counters)

    one_of([
      tuple({constant(:put), key, value()}),
      tuple({constant(:put_new), key, value()}),
      tuple({constant(:replace), key, value()}),
      tuple({constant(:put_all), entries(key)}),
      tuple({constant(:put_new_all), entries(key)}),
      tuple({constant(:fetch), any_key}),
      tuple({constant(:has_key?), any_key}),
      tuple({constant(:get), any_key, value()}),
      tuple({constant(:delete), any_key}),
      tuple({constant(:take), any_key}),
      tuple({constant(:incr), counter, amount, default}),
      tuple({constant(:decr), counter, map(amount, &(-&1)), default}),
      tuple({constant(:get_all), key_list(any_key)}),
      constant({:count_all}),
      tuple({constant(:delete_all), key_list(any_key)})
    ])
  end

  defp entries(key) do
    map(list_of(tuple({key, value()}), max_length: 4), &Map.new/1)
  end

  # The docs don't define duplicate keys in `:in`, so lists are unique.
  defp key_list(key) do
    map(list_of(key, max_length: 5), &Enum.uniq/1)
  end

  # Values include `nil`, which is a valid cache value.
  @doc false
  @spec value() :: StreamData.t(any())
  def value do
    one_of([constant(nil), term()])
  end

  ## Model

  @doc false
  @spec step(t(), command()) :: {any(), t()}
  def step(model, command)

  def step(model, {:put, key, value}) do
    {:ok, Map.put(model, key, value)}
  end

  def step(model, {:put_new, key, value}) do
    if Map.has_key?(model, key) do
      {{:ok, false}, model}
    else
      {{:ok, true}, Map.put(model, key, value)}
    end
  end

  def step(model, {:replace, key, value}) do
    if Map.has_key?(model, key) do
      {{:ok, true}, Map.put(model, key, value)}
    else
      {{:ok, false}, model}
    end
  end

  def step(model, {:put_all, entries}) do
    {:ok, Map.merge(model, entries)}
  end

  def step(model, {:put_new_all, entries}) do
    if Enum.any?(entries, fn {key, _} -> Map.has_key?(model, key) end) do
      {{:ok, false}, model}
    else
      {{:ok, true}, Map.merge(model, entries)}
    end
  end

  def step(model, {:fetch, key}) do
    {fetch(model, key), model}
  end

  def step(model, {:has_key?, key}) do
    {{:ok, Map.has_key?(model, key)}, model}
  end

  def step(model, {:get, key, default}) do
    {{:ok, Map.get(model, key, default)}, model}
  end

  def step(model, {:delete, key}) do
    {:ok, Map.delete(model, key)}
  end

  def step(model, {:take, key}) do
    {fetch(model, key), Map.delete(model, key)}
  end

  def step(model, {:incr, key, amount, default}) do
    value = Map.get(model, key, default) + amount

    {{:ok, value}, Map.put(model, key, value)}
  end

  def step(model, {:decr, key, amount, default}) do
    value = Map.get(model, key, default) - amount

    {{:ok, value}, Map.put(model, key, value)}
  end

  def step(model, {:get_all, keys}) do
    {{:ok, Enum.sort(Map.take(model, keys))}, model}
  end

  def step(model, {:count_all}) do
    {{:ok, map_size(model)}, model}
  end

  def step(model, {:delete_all, keys}) do
    {{:ok, Enum.count(keys, &Map.has_key?(model, &1))}, Map.drop(model, keys)}
  end

  defp fetch(model, key) do
    case Map.fetch(model, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, %Nebulex.KeyError{key: key, reason: :not_found}}
    end
  end

  ## Runner

  @doc false
  @spec run!(module(), [command()]) :: t()
  def run!(cache, commands) do
    {:ok, _} = cache.delete_all()

    model =
      commands
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {command, index}, model ->
        model = assert_step!(cache, model, command, index)

        # `fetch`, `has_key?` and `get` agree with the model on every key the
        # command touched.
        for key <- keys_of(command),
            read <- [{:fetch, key}, {:has_key?, key}, {:get, key, :none}] do
          assert_step!(cache, model, read, index)
        end

        model
      end)

    assert_cache!(cache, model)
  end

  @doc false
  @spec assert_cache!(module(), t()) :: t()
  def assert_cache!(cache, model) do
    assert Enum.sort(cache.get_all!()) == Enum.sort(model)
    assert cache.count_all!() == map_size(model)

    model
  end

  defp assert_step!(cache, model, command, index) do
    {expected, model} = step(model, command)

    assert {index, command, exec(cache, command)} == {index, command, expected}

    model
  end

  defp keys_of({:count_all}), do: []
  defp keys_of({op, entries}) when op in [:put_all, :put_new_all], do: Map.keys(entries)
  defp keys_of({op, keys}) when op in [:get_all, :delete_all], do: keys
  defp keys_of(command), do: [elem(command, 1)]

  @doc false
  @spec exec(module(), command()) :: any()
  def exec(cache, command) do
    cache
    |> do_exec(command)
    |> normalize(command)
  end

  defp do_exec(cache, {:put, key, value}), do: cache.put(key, value)
  defp do_exec(cache, {:put_new, key, value}), do: cache.put_new(key, value)
  defp do_exec(cache, {:replace, key, value}), do: cache.replace(key, value)
  defp do_exec(cache, {:put_all, entries}), do: cache.put_all(entries)
  defp do_exec(cache, {:put_new_all, entries}), do: cache.put_new_all(entries)
  defp do_exec(cache, {:fetch, key}), do: cache.fetch(key)
  defp do_exec(cache, {:has_key?, key}), do: cache.has_key?(key)
  defp do_exec(cache, {:get, key, default}), do: cache.get(key, default)
  defp do_exec(cache, {:delete, key}), do: cache.delete(key)
  defp do_exec(cache, {:take, key}), do: cache.take(key)
  defp do_exec(cache, {:incr, key, amount, default}), do: cache.incr(key, amount, default: default)
  defp do_exec(cache, {:decr, key, amount, default}), do: cache.decr(key, amount, default: default)
  defp do_exec(cache, {:get_all, keys}), do: cache.get_all(in: keys)
  defp do_exec(cache, {:count_all}), do: cache.count_all()
  defp do_exec(cache, {:delete_all, keys}), do: cache.delete_all(in: keys)

  # Entries come in no particular order, and a `Nebulex.KeyError` is
  # compared by its key and reason only.
  defp normalize({:ok, entries}, {:get_all, _}), do: {:ok, Enum.sort(entries)}
  defp normalize({:error, %Nebulex.KeyError{} = e}, _command), do: {:error, %{e | metadata: []}}
  defp normalize(result, _command), do: result
end
