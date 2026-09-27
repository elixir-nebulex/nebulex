defmodule Nebulex.Cache.CompositeKVDispatchTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase, only: [setup_with_cache: 1, with_telemetry_handler: 2]

  alias Nebulex.Telemetry

  ## Adapter overriding one composite callback

  defmodule Adapter do
    @moduledoc false

    @behaviour Nebulex.Adapter
    @behaviour Nebulex.Adapter.KV

    use Nebulex.Adapter.CompositeKV

    alias Nebulex.TestAdapter

    @impl true
    defmacro __before_compile__(_env), do: :ok

    @impl true
    defdelegate init(opts), to: TestAdapter

    @impl true
    defdelegate fetch(adapter_meta, key, opts), to: TestAdapter

    @impl true
    defdelegate put(adapter_meta, key, value, on_write, ttl, keep_ttl?, opts), to: TestAdapter

    @impl true
    defdelegate put_all(adapter_meta, entries, on_write, ttl, opts), to: TestAdapter

    @impl true
    defdelegate delete(adapter_meta, key, opts), to: TestAdapter

    @impl true
    defdelegate take(adapter_meta, key, opts), to: TestAdapter

    @impl true
    defdelegate has_key?(adapter_meta, key, opts), to: TestAdapter

    @impl true
    defdelegate ttl(adapter_meta, key, opts), to: TestAdapter

    @impl true
    defdelegate expire(adapter_meta, key, ttl, opts), to: TestAdapter

    @impl true
    defdelegate touch(adapter_meta, key, opts), to: TestAdapter

    @impl true
    defdelegate update_counter(adapter_meta, key, amount, default, ttl, opts), to: TestAdapter

    @impl true
    def get_or_store(_adapter_meta, key, fun, ttl, keep_ttl?, opts) do
      send(self(), {:get_or_store, key, fun, ttl, keep_ttl?, opts})

      {:ok, :overridden}
    end
  end

  defmodule Cache do
    @moduledoc false

    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Cache.CompositeKVDispatchTest.Adapter
  end

  ## Shared constants

  # Telemetry stop event of the cache under test
  @stop Telemetry.default_prefix(Cache) ++ [:command, :stop]

  setup_with_cache Cache

  describe "dispatch" do
    test "runs the adapter callback with the parsed arguments", %{cache: cache} do
      fun = fn -> :unused end
      opts = [ttl: :timer.seconds(10), keep_ttl: true, telemetry_metadata: %{foo: 1}]

      with_telemetry_handler [@stop], fn ->
        assert cache.get_or_store(:key, fun, opts) == {:ok, :overridden}

        assert_received {:get_or_store, :key, ^fun, 10_000, true, [telemetry_metadata: %{foo: 1}]}

        assert_receive {@stop, _, %{command: :get_or_store, result: {:ok, :overridden}} = meta}
        assert meta[:extra_metadata] == %{foo: 1}
      end

      assert cache.has_key?(:key) == {:ok, false}
    end
  end
end
