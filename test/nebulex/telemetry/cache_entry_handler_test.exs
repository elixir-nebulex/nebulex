defmodule Nebulex.Telemetry.CacheEntryHandlerTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase, only: [test_with_dynamic_cache: 3]

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.TestCache.Cache

  describe "unregister_event_listener/3" do
    test "ok: detaches the listener for a cache started without a name" do
      test_with_dynamic_cache(Cache, [name: nil], fn ->
        test_pid = self()
        listener = fn event -> send(test_pid, {:cache_entry_event, event}) end

        :ok = Cache.register_event_listener!(listener)

        assert Cache.put("foo", "bar") == :ok
        assert_receive {:cache_entry_event, %CacheEntryEvent{}}

        :ok = Cache.unregister_event_listener!(listener)

        assert Cache.put("foo", "baz") == :ok
        refute_receive {:cache_entry_event, _}
      end)
    end
  end
end
