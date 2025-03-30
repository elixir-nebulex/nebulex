defmodule Nebulex.Cache.ObservableTest do
  import Nebulex.CacheCase

  deftests do
    import ExUnit.CaptureLog
    import Nebulex.CacheCase, only: [t_sleep: 1]

    alias Nebulex.Event.CacheEntryEvent

    describe "register_event_listener!/2" do
      setup do
        listener = &unquote(__MODULE__).my_listener/1

        {:ok, listener: listener}
      end

      test "ok: registers a listener with id", %{cache: cache, listener: listener} do
        assert cache.register_event_listener!(listener, id: :my_listener) == :ok
      after
        assert cache.unregister_event_listener!(:my_listener) == :ok
      end

      test "ok: registers a listener to listen all events", %{
        cache: cache,
        name: name,
        listener: listener
      } do
        :ok = cache.register_event_listener!(listener)

        event =
          CacheEntryEvent.new(
            cache: cache,
            name: name,
            type: :inserted,
            target: {:key, "foo"},
            command: :put
          )

        assert cache.put("foo", "bar") == :ok
        assert_receive ^event

        updated = %{event | type: :updated, command: :replace}

        assert cache.replace!("foo", "bar bar")
        assert_receive ^updated

        inserted_new = %{event | target: {:key, "foo foo"}, command: :put_new}

        refute cache.put_new!("foo", "bar")
        refute_receive ^inserted_new

        assert cache.put_new!("foo foo", "bar bar")
        assert_receive ^inserted_new

        deleted = %{event | type: :deleted, command: :delete}

        assert cache.delete("foo") == :ok
        assert_receive ^deleted

        entries = [foo: :bar, bar: :foo]
        inserted_all = %{event | target: {:keys, Keyword.keys(entries)}, command: :put_all}

        assert cache.put_all(entries) == :ok
        assert_receive ^inserted_all

        inserted_new_all = %{inserted_all | command: :put_new_all}

        refute cache.put_new_all!(entries)
        refute_receive ^inserted_new_all

        entries = [k1: :v1, k2: :v2]

        inserted_new_all = %{
          inserted_all
          | target: {:keys, Keyword.keys(entries)},
            command: :put_new_all
        }

        assert cache.put_new_all!(entries)
        assert_receive ^inserted_new_all

        deleted_all = %{
          event
          | type: :deleted,
            target: {:query, {:in, [:foo, :bar]}},
            command: :delete_all
        }

        assert cache.delete_all!(in: [:foo, :bar]) == 2
        assert_receive ^deleted_all

        inserted_incr = %{event | command: :incr, target: {:key, :c}}

        assert cache.incr!(:c) == 1
        assert_receive ^inserted_incr

        updated_decr = %{inserted_incr | type: :updated, command: :decr}

        assert cache.decr!(:c) == 0
        assert_receive ^updated_decr

        updated_exp = %{updated_decr | command: :expire}

        assert cache.expire!(:c, 1000)
        assert_receive ^updated_exp

        _ = t_sleep(1010)

        expired = %{updated_decr | type: :expired, command: :fetch}

        refute cache.get!(:c)
        assert_receive ^expired

        deleted_take = %{deleted | command: :take, target: {:key, :k1}}

        assert cache.take!(:k1) == :v1
        assert_receive ^deleted_take

        assert {:error, _} = cache.take(:k1)
        refute_receive ^deleted_take
      after
        assert cache.unregister_event_listener!(listener) == :ok
      end

      test "ok: registers a listener with filter", %{cache: cache, name: name, listener: listener} do
        filter = &unquote(__MODULE__).my_filter/1

        :ok = cache.register_event_listener!(listener, filter: filter)

        event =
          CacheEntryEvent.new(
            cache: cache,
            name: name,
            type: :inserted,
            target: {:key, "test"},
            command: :put
          )

        assert cache.put("test", "test") == :ok
        refute_receive ^event

        updated = %{event | type: :updated, command: :replace}

        assert cache.replace!("test", "test test")
        assert_receive ^updated

        deleted = %{event | type: :deleted, command: :delete}

        assert cache.delete("test") == :ok
        assert_receive ^deleted

        entries = [foo: :bar, bar: :foo]
        inserted_all = %{event | target: {:keys, Keyword.keys(entries)}, command: :put_all}

        assert cache.put_new_all(entries) == {:ok, true}
        refute_receive ^inserted_all

        updated_exp = %{updated | target: {:key, :foo}, command: :expire}

        assert cache.expire!(:foo, 1000)
        assert_receive ^updated_exp

        _ = t_sleep(1010)

        expired = %{updated | type: :expired, command: :fetch}

        refute cache.get!(:foo)
        refute_receive ^expired

        deleted_all = %{
          event
          | type: :deleted,
            target: {:query, {:q, nil}},
            command: :delete_all
        }

        assert cache.delete_all!() == 1
        assert_receive ^deleted_all
      after
        assert cache.unregister_event_listener!(listener) == :ok
      end

      test "ok: registers a listener with metadata (keyword)", %{
        cache: cache,
        name: name,
        listener: listener
      } do
        :ok = cache.register_event_listener!(listener, metadata: [foo: :bar])

        event =
          CacheEntryEvent.new(
            cache: cache,
            name: name,
            type: :inserted,
            target: {:key, "test"},
            command: :put,
            metadata: [foo: :bar]
          )

        assert cache.put("test", "test") == :ok
        assert_receive ^event
      after
        assert cache.unregister_event_listener!(listener) == :ok
      end

      test "ok: registers a listener with metadata (map)", %{
        cache: cache,
        name: name,
        listener: listener
      } do
        filter = &unquote(__MODULE__).my_filter_with_meta/1
        metadata = %{{:foo, "bar"} => {:foo, "bar"}, "string" => "string", atom: :atom}

        :ok = cache.register_event_listener!(listener, filter: filter, metadata: metadata)

        event =
          CacheEntryEvent.new(
            cache: cache,
            name: name,
            type: :inserted,
            target: {:key, "test"},
            command: :put,
            metadata: metadata
          )

        assert cache.put("test", "test") == :ok
        assert_receive ^event
      after
        assert cache.unregister_event_listener!(listener) == :ok
      end

      test "ok: events ignored due to cache name mismatch", %{
        cache: cache,
        name: name,
        listener: listener
      } do
        {:ok, pid} = cache.start_link(name: :my_temp_observable_cache)

        try do
          assert cache.register_event_listener!(listener, id: :my_listener) == :ok

          assert cache.register_event_listener!(:my_temp_observable_cache, listener,
                   id: :my_listener
                 ) == :ok

          event1 =
            CacheEntryEvent.new(
              cache: cache,
              name: name,
              type: :inserted,
              target: {:key, "test"},
              command: :put
            )

          event2 = %{event1 | name: :my_temp_observable_cache}

          assert cache.put("test", "test") == :ok
          assert_receive ^event1
          refute_receive ^event2

          assert cache.put(:my_temp_observable_cache, "test", "test", []) == :ok
          assert_receive ^event2
          refute_receive ^event1
        after
          :ok = cache.unregister_event_listener!(:my_listener)
          :ok = cache.unregister_event_listener!(:my_temp_observable_cache, :my_listener, [])
          :ok = cache.stop(pid, [])
        end
      end

      test "error: listener is already registered", %{cache: cache, listener: listener} do
        :ok = cache.register_event_listener!(listener)

        assert_raise Nebulex.Error,
                     ~r"another cache entry listener with the same ID already exists",
                     fn ->
                       cache.register_event_listener!(listener)
                     end
      after
        assert cache.unregister_event_listener!(listener) == :ok
      end

      test "error: listener raises an exception", %{cache: cache} do
        listener = &unquote(__MODULE__).error_listener/1
        :ok = cache.register_event_listener!(listener)

        try do
          assert capture_log(fn -> cache.put!("some", "error") end) =~
                   "has failed and has been detached"
        after
          assert cache.unregister_event_listener!(listener) == :ok
        end
      end

      test "error: listener exists", %{cache: cache} do
        listener = &unquote(__MODULE__).exit_listener/1
        :ok = cache.register_event_listener!(listener)

        try do
          assert capture_log(fn -> cache.put!("some", "error") end) =~
                   "has failed and has been detached"
        after
          assert cache.unregister_event_listener!(listener) == :ok
        end
      end

      test "error: listener processing exception" do
        assert_raise Nebulex.Error,
                     ~r"cache entry event listener failed when processing an event",
                     fn ->
                       raise Nebulex.Error,
                         reason: :event_listener_error,
                         original: %RuntimeError{},
                         event: :test,
                         listener: :test
                     end
      end
    end

    def my_listener(event) do
      send(self(), event)
    end

    def my_filter(%CacheEntryEvent{type: type}) do
      if type in [:deleted, :updated] do
        true
      else
        false
      end
    end

    def error_listener(event) do
      raise "error #{inspect(event)}"
    end

    def exit_listener(event) do
      exit({:exit_listener, event})
    end

    def my_filter_with_meta(_event), do: true
  end
end
