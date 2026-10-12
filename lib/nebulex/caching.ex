if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Caching do
    @moduledoc """
    Applies caching to Elixir functions so they run fewer times. Each time a
    decorated function is called, the decorator checks whether a result for
    the given arguments is already in the cache. If it is, the cached result
    is returned and the function body is skipped. If it is not, the function
    runs, its result is stored in the cache, and the next call with the same
    arguments gets the cached result. An expensive function (CPU or IO bound)
    therefore runs once per set of arguments. The caller does not see any of
    this; it calls the function as usual.

    See **`Nebulex.Caching.Decorators`** to learn more about the caching
    decorators and their usage.

    ## Compilation time options

    The following are the available compilation time options when defining
    the caching usage via `use Nebulex.Caching`:

    #{Nebulex.Caching.Options.use_options_docs()}

    See the ["Shared Options"][shared_opts] section in the decorators module
    for more information.

    [shared_opts]: `m:Nebulex.Caching.Decorators#module-shared-options`

    > #### `use Nebulex.Caching, opts` {: .info}
    >
    > These options are defaults for all decorated functions in the module;
    > each decorator declaration can override them. For example, if every
    > decorated function in a module uses the same cache, set it once:
    >
    > ```elixir
    > use Nebulex.Caching, cache: MyCache
    > ```
    >
    > and leave the `:cache` option out of the decorator declarations.
    """

    alias Nebulex.Caching.{Decorators, Options}

    @doc false
    defmacro __using__(opts \\ []) do
      quote bind_quoted: [opts: opts] do
        # Validate options
        opts =
          opts
          |> Macro.escape()
          |> Options.validate_use_opts!()

        # Set the __using__ macro options so they can be used in the decorators
        :ok = Module.put_attribute(__MODULE__, :__caching_opts__, opts)

        use Nebulex.Caching.Decorators

        import Nebulex.Caching, only: [dynamic_cache: 2, keyref: 1, keyref: 2]
      end
    end

    @doc """
    Creates a dynamic cache tuple form to use in the decorated function
    (wrapper macro for `Nebulex.Caching.Decorators.dynamic_cache_spec/2`).

    The first argument, `cache`, specifies the defined cache module,
    and the second argument, `name`, is the actual name of the cache.

    > #### Using `dynamic_cache` {: .info}
    >
    > `use Nebulex.Caching` imports this macro, so it is available in the
    > module without further setup.

    ## Example

        defmodule MyApp.Users do
          use Nebulex.Caching

          @decorate cacheable(cache: dynamic_cache(MyApp.Cache, :users))
          def get_user(id) do
            # your logic ...
          end
        end

    See the ["Cache configuration"](`m:Nebulex.Caching.Decorators#module-cache-configuration`)
    section in the `Nebulex.Caching.Decorators` module documentation for more
    information.
    """
    defmacro dynamic_cache(cache, name) do
      quote do
        Decorators.dynamic_cache_spec(unquote(cache), unquote(name))
      end
    end

    @doc """
    Creates a reference tuple form to use in the decorated function
    (wrapper macro for `Nebulex.Caching.Decorators.keyref_spec/3`).

    > #### Using `keyref` {: .info}
    >
    > `use Nebulex.Caching` imports this macro, so it is available in the
    > module without further setup.

    ## Options

      * `:cache` - The cache where the referenced key is stored.

      * `:ttl` - The TTL for the referenced key. If configured, it overrides
        the TTL given in the decorator's option `:opts`.

    See `Nebulex.Caching.Decorators.cacheable/3` decorator
    for more information.
    """
    defmacro keyref(key, opts \\ []) do
      cache = Keyword.get(opts, :cache)
      ttl = Keyword.get(opts, :ttl)

      quote do
        Decorators.keyref_spec(unquote(cache), unquote(key), unquote(ttl))
      end
    end
  end
end
