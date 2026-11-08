defmodule Nebulex.Cache.CompositeKVPropTest do
  import Nebulex.CacheCase

  deftests do
    use ExUnitProperties

    alias Nebulex.CacheModel

    # Each property runs a generated command sequence first, so the composite
    # command starts from a random state with the key present or missing.

    # Runs per property. Each run also runs a command prefix, so these use
    # fewer runs than the default to keep the shared suite fast.
    @composite_kv_max_runs 50

    describe "CompositeKV laws" do
      property "get_and_update returns the function's result and stores the new value",
               %{cache: cache} do
        check all pool <- CacheModel.key_pool(),
                  commands <- CacheModel.commands(pool),
                  key <- member_of(pool),
                  get <- CacheModel.value(),
                  new <- CacheModel.value(),
                  max_runs: @composite_kv_max_runs do
          model = CacheModel.run!(cache, commands)

          fun = fn current ->
            send(self(), {:current, current})

            {get, new}
          end

          assert cache.get_and_update!(key, fun) == {get, new}
          assert_received {:current, current}
          assert current == Map.get(model, key)

          CacheModel.assert_cache!(cache, Map.put(model, key, new))
        end
      end

      property "get_and_update deletes the key when the function returns :pop", %{cache: cache} do
        check all pool <- CacheModel.key_pool(),
                  commands <- CacheModel.commands(pool),
                  key <- member_of(pool),
                  max_runs: @composite_kv_max_runs do
          model = CacheModel.run!(cache, commands)

          assert cache.get_and_update!(key, fn _ -> :pop end) == {Map.get(model, key), nil}

          CacheModel.assert_cache!(cache, Map.delete(model, key))
        end
      end

      property "update stores initial on a missing key and fun.(value) on an existing one",
               %{cache: cache} do
        check all pool <- CacheModel.key_pool(),
                  commands <- CacheModel.commands(pool),
                  key <- member_of(pool),
                  initial <- CacheModel.value(),
                  new <- CacheModel.value(),
                  max_runs: @composite_kv_max_runs do
          model = CacheModel.run!(cache, commands)

          fun = fn value ->
            send(self(), {:value, value})

            new
          end

          case Map.fetch(model, key) do
            {:ok, value} ->
              assert cache.update!(key, initial, fun) == new
              assert_received {:value, ^value}

              CacheModel.assert_cache!(cache, Map.put(model, key, new))

            :error ->
              assert cache.update!(key, initial, fun) == initial
              refute_received {:value, _}

              CacheModel.assert_cache!(cache, Map.put(model, key, initial))
          end
        end
      end

      property "fetch_or_store is idempotent and calls the function at most once",
               %{cache: cache} do
        check all pool <- CacheModel.key_pool(),
                  commands <- CacheModel.commands(pool),
                  key <- member_of(pool),
                  value <- CacheModel.value(),
                  max_runs: @composite_kv_max_runs do
          model = CacheModel.run!(cache, commands)

          fun = fn ->
            send(self(), :called)

            {:ok, value}
          end

          expected = Map.get(model, key, value)

          assert cache.fetch_or_store(key, fun) == {:ok, expected}
          assert cache.fetch_or_store(key, fun) == {:ok, expected}

          # The function runs only when the key is missing, and only once.
          if not Map.has_key?(model, key), do: assert_received(:called)
          refute_received :called

          CacheModel.assert_cache!(cache, Map.put(model, key, expected))
        end
      end

      property "get_or_store is idempotent and calls the function at most once",
               %{cache: cache} do
        check all pool <- CacheModel.key_pool(),
                  commands <- CacheModel.commands(pool),
                  key <- member_of(pool),
                  value <- CacheModel.value(),
                  max_runs: @composite_kv_max_runs do
          model = CacheModel.run!(cache, commands)

          fun = fn ->
            send(self(), :called)

            value
          end

          expected = Map.get(model, key, value)

          assert cache.get_or_store(key, fun) == {:ok, expected}
          assert cache.get_or_store(key, fun) == {:ok, expected}

          # The function runs only when the key is missing, and only once.
          if not Map.has_key?(model, key), do: assert_received(:called)
          refute_received :called

          CacheModel.assert_cache!(cache, Map.put(model, key, expected))
        end
      end
    end
  end
end
