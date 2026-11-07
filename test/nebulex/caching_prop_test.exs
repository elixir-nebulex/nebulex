defmodule Nebulex.CachingPropTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Nebulex.CacheCase, only: [setup_with_cache: 1]

  ## Internals

  defmodule Cache do
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
end
