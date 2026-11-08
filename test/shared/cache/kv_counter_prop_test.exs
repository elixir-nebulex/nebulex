defmodule Nebulex.Cache.KVCounterPropTest do
  import Nebulex.CacheCase

  deftests do
    use ExUnitProperties

    # The laws compare two calls on two keys that start in the same state,
    # so the expected values never re-implement the counter arithmetic.

    describe "counter laws" do
      property "incr on a missing key behaves as if the key held the default",
               %{cache: cache} do
        check all [missing, stored] <- uniq_list_of(term(), length: 2),
                  amount <- integer(),
                  default <- integer() do
          {:ok, _} = cache.delete_all(in: [missing, stored])
          :ok = cache.put(stored, default)

          assert cache.incr!(missing, amount, default: default) == cache.incr!(stored, amount)
          assert cache.fetch!(missing) == cache.fetch!(stored)
        end
      end

      property "two increments compose into one", %{cache: cache} do
        check all [k1, k2] = keys <- uniq_list_of(term(), length: 2),
                  initial <- initial(),
                  a <- integer(),
                  b <- integer(),
                  default <- integer() do
          :ok = reset_counters!(cache, keys, initial)

          _ = cache.incr!(k1, a, default: default)

          assert cache.incr!(k1, b, default: default) == cache.incr!(k2, a + b, default: default)
          assert cache.fetch!(k1) == cache.fetch!(k2)
        end
      end

      property "decr(key, amount) behaves like incr(key, -amount)", %{cache: cache} do
        check all [k1, k2] = keys <- uniq_list_of(term(), length: 2),
                  initial <- initial(),
                  amount <- integer(),
                  default <- integer() do
          :ok = reset_counters!(cache, keys, initial)

          assert cache.decr!(k1, amount, default: default) ==
                   cache.incr!(k2, -amount, default: default)

          assert cache.fetch!(k1) == cache.fetch!(k2)
        end
      end
    end

    # Both keys are missing, or both hold the same integer.
    defp initial do
      one_of([constant(:missing), integer()])
    end

    defp reset_counters!(cache, keys, initial) do
      {:ok, _} = cache.delete_all(in: keys)

      if initial == :missing, do: :ok, else: cache.put_all(Map.new(keys, &{&1, initial}))
    end
  end
end
