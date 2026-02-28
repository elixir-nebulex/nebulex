defmodule Nebulex do
  @moduledoc """
  Nebulex is split into two main components:

    * `Nebulex.Cache` - Defines a standard Cache API for caching data.
      This API implementation is intended to create a way for different
      technologies to provide a common caching interface. It defines the
      mechanism for creating, accessing, updating, and removing information
      from a cache. This common interface makes it easier for software
      developers to leverage various technologies as caches since the
      software they write using the Nebulex Cache API does not need
      to be rewritten to work with different underlying technologies.

    * `Nebulex.Caching` - Defines a Cache Abstraction for transparently adding
      caching into an existing Elixir application. The caching abstraction
      allows consistent use of various caching solutions with minimal impact
      on the code. This Cache Abstraction enables declarative decorator-based
      caching via **`Nebulex.Caching.Decorators`**. Decorators provide an
      elegant way of annotating functions to be cached or evicted. Caching
      decorators also enable the adoption or implementation of cache usage
      patterns such as **Read-through**, **Write-through**, **Cache-as-SoR**,
      etc. See the [Cache Usage Patterns](cache-usage-patterns.md) guide.

  The following sections will provide an overview of those components and their
  usage. Feel free to access their respective module documentation for more
  specific examples, options, and configurations.

  If you want to check a sample application using Nebulex quickly, please check
  the [getting started guide](getting-started.md).

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

  To provide more flexibility and load only the needed dependencies,
  Nebulex makes all dependencies optional, including the adapters.

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

  `Nebulex.Cache` is the wrapper around the Cache. We can define a
  cache as follows:

      defmodule MyApp.MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MyCache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_memory_check_interval: :timer.seconds(10)

  Each cache in Nebulex defines a `start_link/1` function that needs to be
  invoked before using the cache. In general, this function is not called
  directly, but used as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the cache as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, []}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  Otherwise, you can start and stop the cache directly at any time by calling
  `MyApp.Cache.start_link/1` and `MyApp.Cache.stop/1`.

  ## What's next

    * 🚀 [Getting Started](getting-started.md) - Set up Nebulex and
      learn the basics of caching.
    * 🔌 [Nebulex Adapters](nbx-adapters.md) - Explore available
      adapters and choose the right one.
    * ✨ [Declarative Caching](declarative-caching.md) - Learn
      decorator-based caching with `Nebulex.Caching`.
    * 📐 [Cache Usage Patterns](cache-usage-patterns.md) - Implement
      Read-through, Write-through, and other patterns.
    * 📊 [Info API](info-api.md) - Monitor cache stats, memory,
      and telemetry.
    * 🔧 [Creating a New Adapter](creating-new-adapter.md) - Build
      custom adapters for your caching needs.
    * ⬆️ [Upgrading to v3.0](v3-0.html) - Migration guide from
      previous versions.

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
