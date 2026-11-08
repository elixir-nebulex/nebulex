defmodule Nebulex.CachingPropTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Nebulex.CacheCase, only: [setup_with_cache: 1]
  import Nebulex.Caching, only: [keyref: 1, keyref: 2]

  alias Nebulex.Caching.Decorators
  alias Nebulex.Caching.Decorators.Context

  ## Internals

  defmodule Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  defmodule OtherCache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  defmodule Decorated do
    @moduledoc false
    use Nebulex.Caching, cache: Cache

    # The decorated functions count their body runs and key function calls in
    # the process dictionary of the caller.

    @decorate cacheable(key: key, match: &match/1)
    def get(key, value, cache?), do: body({key, value, cache?})

    @decorate cache_evict(key: key)
    def evict(key), do: body(key)

    @decorate cacheable(key: &counted_key/1)
    def counted_get(key, value), do: body({key, value})

    @decorate cacheable(key: &counted_key/1, transaction: true)
    def counted_get_txn(key, value), do: body({key, value})

    @decorate cache_put(key: &counted_key/1)
    def counted_put(key, value), do: body({key, value})

    @decorate cache_put(key: &counted_key/1, transaction: true)
    def counted_put_txn(key, value), do: body({key, value})

    @decorate cache_evict(key: &counted_key/1)
    def counted_evict(key, value), do: body({key, value})

    @decorate cache_evict(key: &counted_key/1, transaction: true)
    def counted_evict_txn(key, value), do: body({key, value})

    # The key function returns `{:in, refs}`, where refs mix plain keys and
    # key references to `Cache` or `OtherCache`.
    @decorate cache_put(key: &refs_key/1)
    def put_refs(refs, value) when is_list(refs), do: value

    @decorate cache_evict(key: &refs_key/1)
    def evict_refs(refs) when is_list(refs), do: :ok

    def refs_key(%{args: [refs | _]}), do: {:in, refs}

    def match({_key, _value, cache?}), do: cache?

    def counted_key(%{args: [key | _]}) do
      _ = bump(:key_calls)

      key
    end

    def calls(counter), do: Process.get(counter, 0)

    defp body(result) do
      _ = bump(:body_calls)

      result
    end

    defp bump(counter), do: Process.put(counter, calls(counter) + 1)
  end

  # Decorated functions whose key is a counting function.
  @counted_funs ~w(
    counted_get counted_get_txn
    counted_put counted_put_txn
    counted_evict counted_evict_txn
  )a

  ## Tests

  setup_with_cache Cache
  setup_with_cache OtherCache

  describe "decorator laws" do
    property "cacheable runs the body once when match holds, every time when not" do
      check all key <- term(), value <- term(), cache? <- boolean() do
        {:ok, _} = Cache.delete_all()
        before = Decorated.calls(:body_calls)

        assert Decorated.get(key, value, cache?) == {key, value, cache?}
        assert Decorated.get(key, value, cache?) == {key, value, cache?}
        assert Decorated.calls(:body_calls) - before == if(cache?, do: 1, else: 2)
      end
    end

    property "cacheable runs the body again after cache_evict on its key" do
      check all key <- term(), value <- term() do
        {:ok, _} = Cache.delete_all()
        before = Decorated.calls(:body_calls)

        assert Decorated.get(key, value, true) == {key, value, true}
        assert Decorated.get(key, value, true) == {key, value, true}
        assert Decorated.evict(key) == key
        assert Decorated.get(key, value, true) == {key, value, true}
        assert Decorated.calls(:body_calls) - before == 3
      end
    end

    property "a key function runs once per call, with or without a transaction" do
      check all fun <- member_of(@counted_funs),
                key <- term(),
                value <- term(),
                calls <- integer(1..3) do
        {:ok, _} = Cache.delete_all()
        before = Decorated.calls(:key_calls)

        for _ <- 1..calls do
          assert apply(Decorated, fun, [key, value]) == {key, value}
        end

        assert {fun, Decorated.calls(:key_calls) - before} == {fun, calls}
      end
    end
  end

  describe "helpers" do
    property "the default key generator is 0, the only arg, or a function of the args" do
      check all args <- list_of(term(), max_length: 4) do
        key = Decorators.generate_key(context(args))

        case args do
          [] -> assert key == 0
          [arg] -> assert key == arg
          _ -> assert Decorators.generate_key(context(copy(args))) == key
        end
      end
    end

    property "cache_put with {:in, refs} puts each key into the cache it refers to" do
      check all refs <- refs(), value <- term() do
        {:ok, _} = Cache.delete_all()
        {:ok, _} = OtherCache.delete_all()

        assert Decorated.put_refs(Enum.map(refs, &to_ref/1), value) == value

        assert Enum.sort(Cache.get_all!()) == entries(refs, [:key, :ref], value)
        assert Enum.sort(OtherCache.get_all!()) == entries(refs, [:other_ref], value)
      end
    end

    property "cache_evict with {:in, refs} deletes each key from the cache it refers to" do
      check all refs <- refs() do
        # Both caches hold every key, plus one that no ref targets.
        all = [{make_ref(), :extra} | keys(refs, [:key, :ref, :other_ref])]

        for cache <- [Cache, OtherCache] do
          {:ok, _} = cache.delete_all()
          :ok = cache.put_all(Map.new(all, &{&1, &1}))
        end

        assert Decorated.evict_refs(Enum.map(refs, &to_ref/1)) == :ok

        assert Enum.sort(Cache.get_all!(select: :key)) ==
                 Enum.sort(all -- keys(refs, [:key, :ref]))

        assert Enum.sort(OtherCache.get_all!(select: :key)) ==
                 Enum.sort(all -- keys(refs, [:other_ref]))
      end
    end
  end

  defp context(args) do
    %Context{decorator: :cacheable, module: __MODULE__, function_name: :fun, args: args}
  end

  # A structurally equal copy built from scratch.
  defp copy(term) do
    term
    |> :erlang.term_to_binary()
    |> :erlang.binary_to_term()
  end

  # A plain key, a reference with no cache (the decorator's cache), or a
  # reference to `OtherCache`. The same key may appear with several kinds.
  defp refs do
    uniq_list_of(tuple({member_of([:key, :ref, :other_ref]), term()}), min_length: 1)
  end

  defp to_ref({:key, key}), do: key
  defp to_ref({:ref, key}), do: keyref(key)
  defp to_ref({:other_ref, key}), do: keyref(key, cache: OtherCache)

  defp keys(refs, kinds) do
    for {kind, key} <- refs, kind in kinds, uniq: true, do: key
  end

  defp entries(refs, kinds, value) do
    refs
    |> keys(kinds)
    |> Enum.map(&{&1, value})
    |> Enum.sort()
  end
end
