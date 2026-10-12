defmodule Nebulex do
  @moduledoc """
  Nebulex is split into two main components:

    * `Nebulex.Cache` - Defines a standard Cache API for caching data.
      The API gives different technologies a common caching interface. It
      defines how to create, read, update, and remove entries from a cache.
      Code written against the Nebulex Cache API does not need to be
      rewritten to work with a different backend.

    * `Nebulex.Caching` - Defines a Cache Abstraction for adding caching to
      an existing Elixir application with little change to the code. It
      provides declarative, decorator-based caching via
      `Nebulex.Caching.Decorators`. Decorators annotate functions so their
      results are cached or evicted. They also cover cache usage patterns
      such as Read-through, Write-through, and Cache-as-SoR. See the
      [Cache Usage Patterns](cache-usage-patterns.md) guide.

  The sections below give an overview of both. See each module's
  documentation for more examples, options, and configuration.

  For a sample application, see the [getting started guide](getting-started.md).

  ## Installation

  To use Nebulex, add both `:nebulex` and your chosen cache adapter as
  dependencies in your `mix.exs` file. Since Nebulex v3, adapters are
  provided as separate packages, so you must include them explicitly.

  For example, to use the Generational Local Cache
  (`Nebulex.Adapters.Local` adapter):

      defp deps do
        [
          {:nebulex, "~> 3.0"},
          {:nebulex_local, "~> 3.0"},
          {:decorator, "~> 1.4"},
          {:telemetry, "~> 1.0"}
        ]
      end

  Apart from `:nimble_options`, every Nebulex dependency is optional,
  including the adapters, so you only load what you need.

    * `:decorator` - Required for
      [declarative decorator-based caching](`Nebulex.Caching`).
    * `:telemetry` - Required for Telemetry events. See the
      [Info API guide](info-api.md) for monitoring cache stats
      and metrics.

  > #### Adapter dependency is required {: .warning}
  >
  > Without the adapter dependency (e.g., `:nebulex_local`), the
  > adapter module will not be available and your cache will fail
  > to start. Make sure to add the appropriate adapter package for
  > the adapter you configure.

  For more information about available adapters and their packages,
  see the [Nebulex adapters](nbx-adapters.md) guide.

  ## Usage

  A cache is a module that uses `Nebulex.Cache`:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  The cache configuration goes in your application environment, usually in
  `config/config.exs`:

      config :my_app, MyApp.Cache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_memory_check_interval: :timer.seconds(10)

  Each cache defines a `start_link/1` function that must run before the
  cache is used. You rarely call it directly; the cache is usually started
  from your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`), `lib/my_app/application.ex` has the application start
  callback that defines and starts your supervisor. Add the cache to the
  children in `start/2`:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, []}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  You can also start and stop the cache yourself at any time with
  `MyApp.Cache.start_link/1` and `MyApp.Cache.stop/1`.

  ## What's next

    * [Getting Started](getting-started.md) - Set up Nebulex and learn the
      basics of caching.
    * [Nebulex Adapters](nbx-adapters.md) - The available adapters and
      how to pick one.
    * [Declarative Caching](declarative-caching.md) - Decorator-based
      caching with `Nebulex.Caching`.
    * [Cache Usage Patterns](cache-usage-patterns.md) - Read-through,
      Write-through, and other patterns.
    * [Info API](info-api.md) - Cache stats, memory, and telemetry.
    * [Creating a New Adapter](creating-new-adapter.md) - How to write
      your own adapter.
    * [Upgrading to v3.0](v3-0.html) - Migration guide from previous
      versions.

  """

  ## API

  @doc """
  Returns the current Nebulex version.
  """
  @spec vsn() :: binary()
  def vsn do
    Application.spec(:nebulex, :vsn)
    |> to_string()
  end
end
