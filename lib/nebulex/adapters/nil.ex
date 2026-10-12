defmodule Nebulex.Adapters.Nil do
  @moduledoc """
  The Nil adapter is a special cache adapter that turns off the cache. It
  drops everything written to it, behaves as if every key were missing on
  reads, and reports success on all writes. It is mostly useful for tests.

  ## Shared options

  All of the cache functions accept the following options
  when using this adapter:

  #{Nebulex.Adapters.Nil.Options.runtime_shared_options_docs()}

  ## Example

  Suppose you have an application that uses Ecto for database access and
  Nebulex for caching, so it defines a repo and a cache. In some tests you may
  want to turn the cache off. For example, a test that expects no data from
  the database can still get data from the cache if the cache was not
  flushed, so you would have to delete all entries before each test. Instead
  of adding code to flush the cache before each test, you can define a test
  cache that uses the Nil adapter.

  The application cache is defined in `lib/my_app/cache.ex`:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  The test cache is defined in `test/support/test_cache.ex`:

      defmodule MyApp.TestCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Nil
      end

  Then tell the app which cache to use per environment: `MyApp.TestCache` in
  tests and `MyApp.Cache` otherwise. One way is a config parameter that picks
  the cache module. In `config/test.exs`:

      config :my_app,
        nebulex_cache: MyApp.TestCache,
        ...

  The last piece is to read the config parameter and start that cache. In
  `lib/my_app/application.ex`:

      def start(_type, _args) do
        children = [
          {Application.get_env(:my_app, :nebulex_cache, MyApp.Cache), []},
        ]

        ...

  `MyApp.Cache` is used by default unless the `:nebulex_cache` option points
  to a different module, which is the case in the `test` environment.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.KV
  @behaviour Nebulex.Adapter.Queryable
  @behaviour Nebulex.Adapter.Transaction

  # Inherit default info implementation
  use Nebulex.Adapters.Common.Info

  # Inherit default observable implementation
  use Nebulex.Adapter.Observable

  # Inherit default composite KV implementation
  use Nebulex.Adapter.CompositeKV

  import Nebulex.Utils, only: [wrap_error: 2]

  alias __MODULE__.Options
  alias Nebulex.Adapters.Common.Info.Stats

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_env), do: :ok

  @impl true
  def init(opts) do
    telemetry_prefix = Keyword.fetch!(opts, :telemetry_prefix)

    child_spec = Supervisor.child_spec({Agent, fn -> :ok end}, id: Agent)

    {:ok, child_spec, %{stats_counter: Stats.init(telemetry_prefix)}}
  end

  ## Nebulex.Adapter.KV

  @impl true
  def fetch(_adapter_meta, key, opts) do
    with_hooks(opts, wrap_error(Nebulex.KeyError, key: key))
  end

  @impl true
  def put(_, _, _, _, _, _, opts) do
    with_hooks(opts, {:ok, true})
  end

  @impl true
  def put_all(_, _, _, _, opts) do
    with_hooks(opts, {:ok, true})
  end

  @impl true
  def delete(_, _, opts) do
    with_hooks(opts, :ok)
  end

  @impl true
  def take(_adapter_meta, key, opts) do
    with_hooks(opts, wrap_error(Nebulex.KeyError, key: key))
  end

  @impl true
  def has_key?(_, _, opts) do
    with_hooks(opts, {:ok, false})
  end

  @impl true
  def ttl(_adapter_meta, key, opts) do
    with_hooks(opts, wrap_error(Nebulex.KeyError, key: key))
  end

  @impl true
  def expire(_, _, _, opts) do
    with_hooks(opts, {:ok, false})
  end

  @impl true
  def touch(_, _, opts) do
    with_hooks(opts, {:ok, false})
  end

  @impl true
  def update_counter(_, _, amount, default, _, opts) do
    with_hooks(opts, {:ok, default + amount})
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  def execute(adapter_meta, query_spec, opts)

  def execute(_, %{op: :get_all}, opts) do
    with_hooks(opts, {:ok, []})
  end

  def execute(_, _, opts) do
    with_hooks(opts, {:ok, 0})
  end

  @impl true
  def stream(_, _, opts) do
    with_hooks(opts, {:ok, Stream.each([], & &1)})
  end

  ## Nebulex.Adapter.Transaction

  @impl true
  def transaction(_, fun, opts) do
    with_hooks(opts, {:ok, fun.()})
  end

  @impl true
  def in_transaction?(_, opts) do
    with_hooks(opts, {:ok, false})
  end

  ## Private functions

  defp with_hooks([], result) do
    result
  end

  defp with_hooks(opts, result) do
    opts = Options.validate_runtime_shared_opts!(opts)

    if pre_hook = Keyword.get(opts, :before) do
      pre_hook.()
    end

    if post_hook = Keyword.get(opts, :after_return) do
      post_hook.(result)
    else
      result
    end
  end
end
