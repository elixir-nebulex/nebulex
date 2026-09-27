defmodule Nebulex.Cache.SupervisorTest do
  use ExUnit.Case, async: true

  defmodule MyCache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter

    @impl true
    def init(opts) do
      case Keyword.get(opts, :ignore) do
        true -> :ignore
        false -> opts
      end
    end
  end

  import Nebulex.CacheCase

  alias Nebulex.{Adapter, Telemetry}
  alias Nebulex.TestCache.Cache

  describe "compile_config/1" do
    test "error: missing :otp_app option" do
      assert_raise NimbleOptions.ValidationError, ~r"required :otp_app option not found", fn ->
        Nebulex.Cache.Supervisor.compile_config(adapter: TestAdapter)
      end
    end

    test "error: missing :adapter option" do
      assert_raise NimbleOptions.ValidationError, ~r"required :adapter option not found", fn ->
        Nebulex.Cache.Supervisor.compile_config(otp_app: :nebulex)
      end
    end

    test "error: adapter was not compiled" do
      msg = ~r"invalid value for :adapter option: the module TestAdapter was not compiled"

      assert_raise NimbleOptions.ValidationError, msg, fn ->
        Nebulex.Cache.Supervisor.compile_config(otp_app: :nebulex, adapter: TestAdapter)
      end
    end

    test "error: adapter doesn't implement the required behaviour" do
      msg =
        "invalid value for :adapter option: Nebulex.Cache expects the option value " <>
          "Nebulex.Cache.SupervisorTest.MyAdapter to list Nebulex.Adapter as a behaviour"

      assert_raise NimbleOptions.ValidationError, msg, fn ->
        defmodule MyAdapter do
        end

        defmodule MyCache2 do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: MyAdapter
        end
      end
    end

    test "error: adapter doesn't implement Nebulex.Adapter.KV" do
      msg =
        "invalid value for :adapter option: Nebulex.Cache expects the option value " <>
          "Nebulex.Cache.SupervisorTest.NoKVAdapter to list Nebulex.Adapter.KV as a behaviour"

      assert_raise NimbleOptions.ValidationError, msg, fn ->
        defmodule NoKVAdapter do
          @behaviour Nebulex.Adapter

          @impl true
          defmacro __before_compile__(_env), do: :ok

          @impl true
          def init(_opts), do: {:ok, [], %{}}
        end

        defmodule NoKVCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: NoKVAdapter
        end
      end
    end

    test "error: adapter doesn't implement Nebulex.Adapter.CompositeKV" do
      msg =
        "invalid value for :adapter option: Nebulex.Cache expects the option value " <>
          "Nebulex.Cache.SupervisorTest.NoCompositeKVAdapter to list " <>
          "Nebulex.Adapter.CompositeKV as a behaviour"

      assert_raise NimbleOptions.ValidationError, msg, fn ->
        defmodule NoCompositeKVAdapter do
          @behaviour Nebulex.Adapter
          @behaviour Nebulex.Adapter.KV

          alias Nebulex.TestAdapter

          @impl true
          defmacro __before_compile__(_env), do: :ok

          @impl true
          defdelegate init(opts), to: TestAdapter

          @impl true
          defdelegate fetch(adapter_meta, key, opts), to: TestAdapter

          @impl true
          defdelegate put(adapter_meta, key, value, on_write, ttl, keep_ttl?, opts),
            to: TestAdapter

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
          defdelegate update_counter(adapter_meta, key, amount, default, ttl, opts),
            to: TestAdapter
        end

        defmodule NoCompositeKVCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: NoCompositeKVAdapter
        end
      end
    end

    test "error: invalid value for :adapter option" do
      msg = ~r"invalid value for :adapter option: expected a module"

      assert_raise NimbleOptions.ValidationError, msg, fn ->
        Nebulex.Cache.Supervisor.compile_config(otp_app: :nebulex, adapter: 123)
      end
    end
  end

  describe "start_link/1" do
    test "starts anonymous cache" do
      assert {:ok, pid} = Cache.start_link(name: nil)
      assert Process.alive?(pid)

      assert Cache.stop(pid, []) == :ok
      refute Process.alive?(pid)
    end

    test "starts cache with via" do
      {:ok, _} = Registry.start_link(keys: :unique, name: Registry.ViaTest)
      name = {:via, Registry, {Registry.ViaTest, "test"}}

      assert {:ok, pid} = Cache.start_link(name: name)
      assert Process.alive?(pid)

      assert [{^pid, _}] = Registry.lookup(Registry.ViaTest, "test")

      assert Cache.stop(pid, []) == :ok
      refute Process.alive?(pid)
    end

    test "starts cache with custom adapter" do
      defmodule CustomCache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.TestCache.AdapterMock
      end

      assert {:ok, _pid} = CustomCache.start_link(child_name: :custom_cache)

      _ = Process.flag(:trap_exit, true)

      assert {:error, _reason} =
               CustomCache.start_link(name: :another_custom_cache, child_name: :custom_cache)

      assert CustomCache.stop() == :ok
    end

    test "starts cache with [bypass_mode: true]" do
      assert {:ok, pid} = Cache.start_link(bypass_mode: true)
      assert Process.alive?(pid)

      assert Adapter.lookup_meta(Cache).adapter == Nebulex.Adapters.Nil

      assert Cache.put("foo", "bar") == :ok
      assert Cache.get!("foo") == nil

      assert Cache.stop(pid, []) == :ok
      refute Process.alive?(pid)
    end

    test "emits telemetry event upon cache start" do
      with_telemetry_handler [[:nebulex, :cache, :init]], fn ->
        {:ok, _} = Cache.start_link(name: :telemetry_test)

        assert_receive {[:nebulex, :cache, :init], _, %{cache: Cache, opts: opts}}
        assert opts[:telemetry_prefix] == Telemetry.default_prefix(Cache)
        assert opts[:name] == :telemetry_test
      end
    end

    test "error: fails on init because :ignore is returned" do
      assert MyCache.start_link(ignore: true) == :ignore
    end
  end

  ## Helpers

  def handle_event(event, measurements, metadata, %{pid: pid}) do
    send(pid, {event, measurements, metadata})
  end
end
