defmodule Nebulex.Cache.KVModelPropTest do
  import Nebulex.CacheCase

  deftests do
    use ExUnitProperties

    alias Nebulex.CacheModel

    describe "KV and Queryable commands" do
      property "any command sequence agrees with the map model", %{cache: cache} do
        check all pool <- CacheModel.key_pool(), commands <- CacheModel.commands(pool) do
          CacheModel.run!(cache, commands)
        end
      end
    end
  end
end
