defmodule Nebulex.Cache.TransactionTest do
  import Nebulex.CacheCase

  deftests do
    describe "transaction/2" do
      test "ok: single transaction", %{cache: cache} do
        assert cache.transaction(fn ->
                 :ok = cache.put!(1, 11)

                 11 = cache.fetch!(1)

                 :ok = cache.delete!(1)

                 cache.get!(1)
               end) == {:ok, nil}
      end

      test "ok: nested transaction", %{cache: cache} do
        assert cache.transaction(fn ->
                 cache.transaction(fn ->
                   :ok = cache.put!(1, 11)

                   11 = cache.fetch!(1)

                   :ok = cache.delete!(1)

                   cache.get!(1)
                 end)
               end) == {:ok, {:ok, nil}}
      end

      test "ok: single transaction with read and write operations", %{cache: cache} do
        assert cache.put(:test, ["old value"]) == :ok
        assert cache.fetch!(:test) == ["old value"]

        assert cache.transaction(fn ->
                 ["old value"] = value = cache.fetch!(:test)

                 :ok = cache.put!(:test, ["new value" | value])

                 cache.fetch!(:test)
               end) == {:ok, ["new value", "old value"]}

        assert cache.fetch!(:test) == ["new value", "old value"]
      end

      test "error: exception is raised", %{cache: cache} do
        assert_raise MatchError, fn ->
          cache.transaction(fn ->
            :ok = cache.put!(1, 11)

            11 = cache.fetch!(1)

            :ok = cache.delete!(1)

            :ok = cache.get(1)
          end)
        end
      end
    end

    describe "in_transaction?/1" do
      test "returns true if calling process is already within a transaction", %{cache: cache} do
        assert cache.in_transaction?() == {:ok, false}

        cache.transaction(fn ->
          :ok = cache.put(1, 11)

          assert cache.in_transaction?() == {:ok, true}
        end)
      end
    end
  end
end
