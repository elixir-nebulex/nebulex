if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Caching.Decorators do
    @moduledoc """
    Declarative decorator-based caching, inspired by
    [Spring Cache Abstraction][spring-cache].

    > *[`decorator`][decorator-lib] library is used underneath.*

    [spring-cache]: https://docs.spring.io/spring/docs/3.2.x/spring-framework-reference/html/cache.html
    [decorator-lib]: https://github.com/arjan/decorator

    There are three function decorators: `cacheable`, `cache_evict`, and
    `cache_put`. They let a function populate or evict the cache as a side
    effect of being called. Let us take a closer look at each decorator.

    ## `cacheable` decorator

    As the name implies, `cacheable` is used to delimit functions that are
    cacheable - that is, functions for whom the result is stored in the cache
    so that on subsequent invocations (with the same arguments), the value is
    returned from the cache without having to execute the function. In its
    simplest form, the decorator declaration requires the cache associated with
    the decorated function if the [default cache](#module-default-cache) is not
    configured (see ["Cache configuration"](#module-cache-configuration)):

        @decorate cacheable(cache: Cache)
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    In the snippet above, the function `find_book/1` is associated with the
    cache named `Cache`. Each time the function is called, the cache is checked
    to see whether the invocation has been already executed and does not have
    to be repeated.

    See `cacheable/3` for more information.

    ## `cache_put` decorator

    For cases where the cache needs to be updated without interfering with the
    function execution, one can use the `cache_put` decorator. That is, the
    function will always be executed and its result placed into the cache
    (according to the `cache_put` options). It supports the same options as
    `cacheable` and should be used for cache population or update rather than
    function flow optimization.

        @decorate cache_put(cache: Cache)
        def update_book(isbn) do
          # the logic for retrieving the book and then updating it ...
        end

    Note that using `cache_put` and `cacheable` decorators on the same function
    is generally discouraged because they have different behaviors. While the
    latter causes the function execution to be skipped by using the cache, the
    former forces the execution in order to execute a cache update. This leads
    to unexpected behavior and with the exception of specific corner-cases
    (such as decorators having conditions that exclude them from each other),
    such declarations should be avoided.

    See `cache_put/3` for more information.

    ## `cache_evict` decorator

    Besides populating the cache, functions can also evict from it, which is
    how stale or unused data is removed. The `cache_evict` decorator marks
    functions that trigger an eviction. Like `cacheable`, it needs the cache
    to act on and accepts a key or a list of keys to evict. It also has the
    `:all_entries` option, which clears the whole cache instead of one or a
    few entries:

        @decorate cache_evict(cache: Cache, all_entries: true)
        def load_books(file_stream) do
          # the logic for loading books ...
        end

    Use `:all_entries` when a whole cache needs to be cleared; removing the
    entries one by one would be slow, so they are removed in one operation as
    shown above.

    The `:before_invocation` option controls whether the eviction happens after
    the function runs (the default) or before. After-invocation eviction works
    like the other decorators: the cache action runs once the function returns
    successfully, so if the function raises, nothing is evicted. With
    `before_invocation: true` the eviction always happens before the function
    is called, which is useful when the eviction should not depend on the
    outcome of the function.

    See `cache_evict/3` for more information.

    ## Shared Options

    All three cache decorators explained previously accept the following
    options:

    #{Nebulex.Caching.Options.shared_options_docs()}

    ## Cache configuration

    The `:cache` option sets the cache for the decorated function. It accepts
    three kinds of value, as documented in the `t:cache/0` type. Let's go over
    them.

    ### Cache module

    The first cache value option is an existing cache module; this is the most
    common value. For example:

        @decorate cacheable(cache: MyApp.Cache)
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    ### Dynamic cache

    In case one is using a dynamic cache:

        @decorate cacheable(cache: dynamic_cache(MyApp.Cache, :books))
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    > See ["Dynamic caches"](`m:Nebulex.Cache#module-dynamic-caches`)
    for more information.

    ### Anonymous function

    Finally, it is also possible to configure an anonymous function to resolve
    the cache value in runtime. The function receives the
    [decorator context](`t:context/0`) as an argument and must return either
    a cache module or a dynamic cache.

        @decorate cacheable(cache: &MyApp.Resolver.resolve_cache/1)
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    Where `resolve_cache` function may look like this:

        defmodule MyApp.Resolver do
          alias Nebulex.Caching.Decorators.Context

          def resolve_cache(%Context{} = context) do
            # the logic for generating the cache value
          end
        end

    ## Default cache

    Setting `:cache` on every decorator gets repetitive when all the decorated
    functions in a module use the same cache. Instead, set it once for the
    whole module in `use Nebulex.Caching`. For example:

        defmodule MyApp.Books do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cacheable()
          def get_book(isbn) do
            # the logic for retrieving a book ...
          end

          @decorate cacheable(cache: MyApp.BestSellersCache)
          def best_sellers do
            # the logic for retrieving best seller books ...
          end

          ...
        end

    In the snippet above, `get_book/1` uses `MyApp.Cache` because its decorator
    has no `:cache` option and the module default applies. A decorator can
    still override the default, as `best_sellers/0` does with a different
    cache.

    Every decorator must end up with a cache: either the module default from
    `use Nebulex.Caching, cache: MyCache` or a `:cache` option in the
    decorator declaration.

    ## Key Generation

    Since caches are essentially key-value stores, each invocation of a cached
    function needs to be translated into a suitable key for cache access. The
    key can be generated using a default key generator (which is configurable)
    or through the decorator option `:key`. Let us take a closer look
    at each approach:

    ### Default Key Generation

    Out of the box, the caching abstraction uses a simple key generator
    strategy given by `Nebulex.Caching.Decorators.generate_key/1`, which is
    based on the following algorithm:

      * If no arguments are given, return `0`.
      * If only one argument is given, return that param as key.
      * If more than one argument is given, return a key computed
        from the hash of all arguments (`:erlang.phash2(args)`).

    One could provide a different key generator via option
    `:default_key_generator`. Once it is configured, the generator will be used
    for each declaration that does not specify its own key generation strategy.
    See ["Custom Key Generation"](#module-custom-key-generation-declaration)
    section down below.

    The following example shows how to configure a custom default key generator:

        defmodule MyApp.Keygen do
          def generate(context) do
            # your key generation logic ...
          end
        end

        defmodule MyApp.Books do
          use Nebulex.Caching,
            cache: MyApp.Cache,
            default_key_generator: &MyApp.Keygen.generate/1

          ...
        end

    The function given to `:default_key_generator` must follow the format
    `&Mod.fun/arity`.

    ### Custom Key Generation Declaration

    Decorated functions often have arguments that should not be part of the
    cache key. This shows up when a function takes several arguments and only
    some of them identify the cached value, while the rest only affect how the
    function runs. For example:

        @decorate cacheable(cache: Cache)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    The two boolean arguments change how the book is found, but they should
    not be part of the key. And what if only one of them matters?

    For such cases, the `:key` option (available in all decorators) lets you
    say how the key is built. You can pick the arguments you need (or fields
    inside them), compute something from them, or call any function. This is
    the recommended approach over the default generator: as a code base grows,
    function signatures vary a lot, and the default strategy rarely fits all
    of them.

    The following are some examples of generating keys:

        @decorate cacheable(cache: Cache, key: isbn)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

        @decorate cacheable(cache: Cache, key: isbn.raw_number)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    It is also possible to use an anonymous function to generate the key.
    The function receives the [decorator's context](`t:context/0`)
    as an argument. For example:

        @decorate cacheable(cache: Cache, key: &{&1.function_name, hd(&1.args)})
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    The key can be also the tuple `{:in, keys}` where `keys` is a list with the
    keys to cache, evict, or update. For example:

        @decorate cache_evict(cache: Cache, key: {:in, [isbn.id, isbn.raw_number]})
        def remove_book(isbn) do
          # the logic for removing the book ...
        end

    The tuple `{:in, [isbn.id, isbn.raw_number]}` instructs the `cache_evict`
    decorator to remove the keys `isbn.id` and `isbn.raw_number` from the
    cache.

    > #### `key: {:in, [...]}` {: .info}
    >
    > The `:key` option only admits the value `{:in, [...]}` for
    > [`cache_evict`](`cache_evict/3`) and [`cache_put`](`cache_put/3`)
    > decorators only. When you need to cache the same value under different
    > keys, you usually decorate multiple functions, like so:
    >
    > ```elixir
    > @decorate cacheable(key: id)
    > def get_user(id)
    >
    > @decorate cacheable(key: email)
    > def get_user_by_email(email)
    > ```
    >
    > See [`cacheable`](`cacheable/3`) decorator for more information.

    ### Custom options

    One can also provide options for the cache commands executed underneath,
    like so:

        @decorate cacheable(cache: Cache, key: isbn, opts: [ttl: :timer.hours(1)])
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    In that case, `opts: [ttl: :timer.hours(1)]` specifies the TTL for the
    cached value.

    See the ["Shared Options"](#module-shared-options) section
    for more information.

    ## Examples

    Supposing an app uses Ecto, and there is a context for accessing books
    `MyApp.Books`, we may decorate some functions as follows:

        # The cache config
        config :my_app, MyApp.Cache,
          gc_interval: 86_400_000, #=> 1 day
          max_size: 1_000_000 #=> Max 1M books

        # The Cache
        defmodule MyApp.Cache do
          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end

        # Book schema
        defmodule MyApp.Books.Book do
          use Ecto.Schema

          schema "books" do
            field(:isbn, :string)
            field(:title, :string)
            field(:author, :string)
            # The rest of the fields omitted
          end

          def changeset(book, attrs) do
            book
            |> cast(attrs, [:isbn, :title, :author])
            |> validate_required([:isbn, :title, :author])
          end
        end

        # Books context
        defmodule MyApp.Books do
          use Nebulex.Caching, cache: MyApp.Cache

          alias MyApp.Repo
          alias MyApp.Books.Book

          @decorate cacheable(key: id)
          def get_book(id) do
            Repo.get(Book, id)
          end

          @decorate cacheable(key: isbn)
          def get_book_by_isbn(isbn) do
            Repo.get_by(Book, [isbn: isbn])
          end

          @decorate cache_put(
                      key: {:in, [book.id, book.isbn]},
                      match: &__MODULE__.match_fun/1
                    )
          def update_book(%Book{} = book, attrs) do
            book
            |> Book.changeset(attrs)
            |> Repo.update()
          end

          def match_fun({:ok, usr}), do: {true, usr}
          def match_fun({:error, _}), do: false

          @decorate cache_evict(key: {:in, [book.id, book.isbn]})
          def delete_book(%Book{} = book) do
            Repo.delete(book)
          end

          def create_book(attrs \\\\ %{}) do
            %Book{}
            |> Book.changeset(attrs)
            |> Repo.insert()
          end
        end

    ## Functions with multiple clauses

    Since [`decorator`](https://github.com/arjan/decorator#functions-with-multiple-clauses)
    library is used, it is important to be aware of its recommendations,
    caveats, limitations, and so on. For instance, for functions with multiple
    clauses the general advice is to create an empty function head, and call
    the decorator on that head, like so:

        @decorate cacheable(cache: Cache)
        def get_user(id \\\\ nil)

        def get_user(nil), do: nil

        def get_user(id) do
          # your logic ...
        end

    However, the previous example works because we are not using the function
    attributes for defining a custom key via the `:key` option. If we add
    `key: id` for instance, we will get errors and/or warnings, since the
    decorator is expecting the attribute `id` to be present, but it is not
    in the first function clause. In other words, when we take this approach,
    is as if the decorator were applied to all function clauses separately.
    To overcome this issue, the arguments used in the decorator must be
    present in the function clauses, which could be achieved in different
    ways. A simple way would be to decorate a wrapper function with the
    arguments the decorator use and do the pattern-matching in a separate
    function.

        @decorate cacheable(cache: Cache, key: id)
        def get_user(id \\\\ nil) do
          do_get_user(id)
        end

        defp do_get_user(nil), do: nil

        defp do_get_user(id) do
          # your logic ...
        end

    Alternatively, you could decorate only the function clause needing the
    caching.

        def get_user(nil), do: nil

        @decorate cacheable(cache: Cache, key: id)
        def get_user(id) do
          # your logic ...
        end

    ## Anonymous functions vs. module captures

    Some options (`:cache`, `:key`, `:references`, `:match`) accept anonymous
    functions. The decorator macro inlines these functions at compile time and
    evaluates them at runtime on every call of the decorated function. In other
    words, each decorated call creates a new function term and runs it once (or
    a few times).

    This is normal and cheap in most cases, but knowing how it works helps you
    write clearer and faster code.

    ### Key points

      * Both anonymous functions (`fn ... end`) and module captures
        (`&Mod.fun/2`) allocate a new function term per invocation.

      * A module capture (`&Mod.fun/arity`) has no environment. It carries no
        extra data, so the allocation is minimal.

      * An anonymous closure may capture variables from its environment. If
        the captured data is large (big maps, structs, lists, configs), every
        decorated call creates a new closure holding references to those
        values, which adds GC pressure on hot paths.

    ### Best practices

      * Small lambdas are fine:

        ```elixir
        key: &(&1 && &1.id)
        references: &(&1 && keyref(&1.id, cache: RedisCache))
        match: &match(&1, email)
        ```

      * Prefer module captures for shared or non-trivial logic. They allocate
        a fresh function per call, but with no environment, which is cheap:

        ```elixir
        key: &MyApp.Keygen.generate/1
        match: &__MODULE__.match_fun/2
        ```

      * If you need the function arguments, use the decorator context instead
        of capturing them:

        ```elixir
        def match_fun(result, %Nebulex.Caching.Decorators.Context{args: [arg]}) do
          check_valid?(result, arg)
        end

        @decorate cacheable(key: arg.id, match: &__MODULE__.match_fun/2)
        def get_user(arg), do: Repo.get(User, arg.id)
        ```

      * Capturing a small or static module attribute (e.g. `@config`) inside
        the lambda is fine. The value is referenced, not copied:

        ```elixir
        # Small config map
        @config %{foo: "bar", baz: "qux"}

        @decorate cacheable(key: id, match: &check_valid?(&1, @config))
        def get_user(id), do: Repo.get(User, id)
        ```

      * If you do use lambdas, keep the captured data small. Instead of
        closing over large maps or configs, fetch what you need inside a
        module function:

        ```elixir
        # Avoid: capturing the full config (large map) in the lambda
        @config %{ttl: :timer.hours(1), cache: MyApp.Cache, extra: %{...}}

        @decorate cacheable(key: id, match: &MyApp.Validator.valid?(&1, @config))
        def get_user(id), do: Repo.get(User, id)

        # Better: fetch what you need inside the module function
        defmodule MyApp.Validator do
          def valid?(result) do
            # or from :persistent_term / ETS / any external source
            config = Application.get_env(:my_app, :validation_config)

            do_validate(result, config)
          end
        end

        @decorate cacheable(key: id, match: &MyApp.Validator.valid?(&1))
        def get_user(id), do: Repo.get(User, id)
        ```

    ### When to care

    The option lambdas run on every call of the decorated function, but
    creating a small or environment-free function term per call costs very
    little.

    You only need to care about this if:

      * The function captures large data structures in its environment.
      * Profiling shows decorator evaluation as a hotspot.

    When in doubt, use a module capture.

    ## Error Handling Strategies

    The `:on_error` option controls what decorators do when a cache operation
    fails (connection lost, memory exhausted, and so on). It does not apply to
    errors raised by your own code, only to cache errors.

    ### `:on_error` with `cacheable`

    **Option 1: `:nothing` (default)** - Keep going

    When a cache error occurs, the function still runs and returns its result,
    just without caching. Use it for caches where a cache failure should not
    break the application.

    ```elixir
    defmodule MyApp.Products do
      use Nebulex.Caching,
        cache: MyApp.Cache,
        on_error: :nothing

      @decorate cacheable(key: id)
      def get_product(id) do
        # If cache fails: function executes, result is returned, no cache storage
        # If cache succeeds: normal read-through caching behavior
        Repo.get(Product, id)
      end
    end

    # Usage:
    MyApp.Products.get_product(1)  # Returns product either way
    ```

    **Option 2: `:raise`** - Fail loudly

    When a cache error occurs, an exception is raised. Use it when a cache
    failure must be visible and stop the operation.

    ```elixir
    defmodule MyApp.SessionCache do
      use Nebulex.Caching,
        cache: MyApp.Cache,
        on_error: :raise

      @decorate cacheable(key: session_id)
      def get_session(session_id) do
        # If cache fails: exception is raised
        # If cache succeeds: normal read-through caching behavior
        Repo.get(Session, session_id)
      end
    end

    # Usage:
    try do
      MyApp.SessionCache.get_session(id)
    rescue
      error -> handle_cache_error(error)
    end
    ```

    ### `:on_error` with `cache_put` and `cache_evict`

    **`:nothing`** - Ignores cache errors; the function result is still returned

    ```elixir
    @decorate cache_put(key: id, on_error: :nothing)
    def update_product(id, attrs) do
      # If cache put fails: error is silently ignored, result is returned
      # If cache put succeeds: data is cached
      Repo.update(...)
    end
    ```

    **`:raise`** - Raises on cache errors

    ```elixir
    @decorate cache_evict(key: id, on_error: :raise)
    def delete_product(id) do
      # If cache delete fails: exception is raised
      # If cache delete succeeds: entry is removed
      Repo.delete(...)
    end
    ```

    ### Decision Guide

    | Scenario | Recommendation | Reasoning |
    |----------|------------------|-----------|
    | **Read cache** | `:nothing` | Cache failures shouldn't break reading |
    | **Critical data** | `:raise` | Failures should be noticed and fixed |
    | **Cache warming** | `:nothing` | Pre-loading failures are non-critical |
    | **Session cache** | `:raise` | Session consistency is critical |
    | **Write-through** | `:nothing` | SoR write succeeds regardless |
    | **Cache invalidation** | `:nothing` | Data is still written to SoR |

    ## Further readings

      * [Cache Usage Patterns Guide](cache-usage-patterns.md).
      * [Declarative Caching Guide](declarative-caching.md).

    """

    # Decorator definitions
    use Decorator.Define,
      cacheable: 0,
      cacheable: 1,
      cache_evict: 0,
      cache_evict: 1,
      cache_put: 0,
      cache_put: 1

    import Nebulex.Utils, only: [get_option: 5]
    import Record

    alias __MODULE__.{Context, Runtime}

    ## Records

    # Dynamic cache spec
    defrecordp(:dynamic_cache, :"$nbx_dynamic_cache_spec", cache: nil, name: nil)

    # Key reference spec
    defrecordp(:keyref, :"$nbx_keyref_spec", cache: nil, key: nil, ttl: nil)

    ## Types

    @typedoc "Proxy type to the decorator context"
    @type context() :: Context.t()

    @typedoc "Type spec for a dynamic cache definition"
    @type dynamic_cache() :: record(:dynamic_cache, cache: module(), name: atom() | pid())

    @typedoc "The type for the cache value"
    @type cache_value() :: module() | dynamic_cache()

    @typedoc """
    The type for the `:cache` option value.

    When defining the `:cache` option on the decorated function,
    the value can be:

      * The defined cache module.
      * A dynamic cache spec created with the macro
        [`dynamic_cache/2`](`Nebulex.Caching.dynamic_cache/2`).
      * An anonymous function to call to resolve the cache value in runtime.
        The function optionally receives the decorator context as an argument
        and must return either a cache module or a dynamic cache.

    """
    @type cache() :: cache_value() | (-> cache_value()) | (context() -> cache_value())

    @typedoc """
    The type for the `:key` option value.

    When defining the `:key` option on the decorated function,
    the value can be:

      * An anonymous function to call to generate the key in runtime.
        The function optionally receives the decorator context as an argument
        and must return the key for caching.

      * The tuple `{:in, keys}`, where `keys` is a list with the keys to evict
        or update (`cache.delete_all(in: keys)` is invoked under the hood).
        The list can also contain key references, in case you need to reference
        a key from another cache. See `t:keyref_spec/0` for more information.

        > **This option is only available for `cache_evict` and `cache_put`
        > decorators.**

      * Any term.

    """
    @type key() :: (-> any()) | (context() -> any()) | {:in, [keyref_spec() | any()]} | any()

    @typedoc "Type for on_error action"
    @type on_error() :: :nothing | :raise

    @typedoc "Type for the match function return"
    @type match_return() :: boolean() | {true, any()} | {true, any(), keyword()}

    @typedoc "Type for match function"
    @type match() ::
            (result :: any() -> match_return())
            | (result :: any(), context() -> match_return())

    @typedoc "Type for a key reference spec"
    @type keyref_spec() ::
            record(:keyref, cache: Nebulex.Cache.t(), key: any(), ttl: timeout() | nil)

    @typedoc "Type for a key reference"
    @type keyref() :: keyref_spec() | any()

    @typedoc "Type for a query"
    @type query() :: (-> any()) | (context() -> any()) | any()

    @typedoc """
    Type spec for the option `:references`.

    When defining the `:references` option on the decorated function,
    the value can be:

      * An anonymous function expects the result of the decorated function
        evaluation as an argument. Alternatively, the decorator context can be
        received as a second argument. It must return the referenced key, which
        could be an explicit key reference spec or any term (see `t:keyref/0`).
        However, `nil` is a special case. Returning `nil` halts the decorator
        execution to prevent a potential cache storage downstream from being
        invoked. If `nil` is meant to be the referenced key, a key reference
        spec must be used (e.g., `keyref(nil)` - see the next item for more
        information).
      * An explicit key reference definition `t:keyref_spec/0`. It must be
        created using the macro [`keyref/2`](`Nebulex.Caching.keyref/2`).
      * Any term. The term is automatically wrapped in a key reference spec,
        assigned to the `:key` field of the spec.

    See `cacheable/3` decorator for more information.
    """
    @type references() ::
            keyref()
            | (result :: any() -> keyref() | any())
            | (result :: any(), context() -> keyref() | any())

    ## Decorator API

    @doc """
    The `cacheable` decorator stores the result of a function in the cache.

    Each time the decorated function is called, the decorator checks whether
    the function has already run for the given arguments. By default the key is
    computed from the function arguments; you can provide your own key with the
    `:key` option or replace the default key generator (see
    ["Key Generation"](#module-key-generation) in the module documentation).

    If there is no value in the cache for the key, the function runs and its
    result is stored in the cache. The `:match` option controls what gets
    cached.

    > #### **Read-through** pattern {: .info}
    >
    > The `cacheable` decorator implements the read-through pattern. Your
    > function is the loader that fetches the value from the system of record
    > (SoR); the decorator does the rest.

    ## Options

    #{Nebulex.Caching.Options.cacheable_options_docs()}

    See the ["Shared options"](#module-shared-options) section in the module
    documentation for more options.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching, cache: MyApp.Cache

          @ttl :timer.hours(1)

          @decorate cacheable(key: id, opts: [ttl: @ttl])
          def get_by_id(id) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(key: email, references: &(&1 && &1.id))
          def get_by_email(email) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(key: clauses, match: &match_fun/1)
          def all(clauses) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          defp match_fun([]), do: false
          defp match_fun(_), do: true
        end

    ## Referenced keys

    Referenced keys are for when several keys hold the same value. Say we have
    a `User` schema with several unique fields: `:id`, `:email`, and `:token`.
    A module may fetch the user account by any of them:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cacheable(key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(key: email)
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(key: token)
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(key: {:in, [user.id, user.email, user.token]})
          def update_user_account(user, attrs) do
            # your logic ...
          end
        end

    All three functions store the same user record under a different key,
    which wastes memory. And when the user record is updated, every cached
    copy has to be invalidated, so the `cache_evict` decorator has to list all
    the keys associated with the user account.

    Referenced keys solve both problems. The module becomes:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cacheable(key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(key: email, references: &(&1 && &1.id))
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(key: token, references: &(&1 && &1.id))
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(key: user.id)
          def update_user_account(user, attrs) do
            # your logic ...
          end
        end

    With `:references`, the `cacheable` decorator stores the user record once,
    under the user ID (the referenced key), and stores the user ID under the
    `email` and `token` keys as references (assuming the function returns a
    user record; if it returns `nil`, nothing is cached). When
    `get_user_account_by_email/1` or `get_user_account_by_token/1` runs, the
    decorator first fetches the reference under `email` or `token`, then
    fetches the user record under the referenced key.

    Since the user record is stored only once, `update_user_account/2` can
    evict just the user ID instead of listing every key. There is a caveat,
    though:

    > #### **Caveat** {: .info}
    >
    > _**`cache_evict` and `cache_put` decorators don't evict or update the
    > references automatically**_.
    >
    > See the ["Eviction of references"](#cache_evict/3-eviction-of-references)
    > section in the `cache_evict` decorator documentation.

    ### The `match` function on references

    The `cacheable` decorator also evaluates the `:match` option's function on
    cache key references to ensure consistency and correctness. Let's give an
    example to understand what this is about.

    Using the previous _"user accounts"_ example, here is the first call to
    get a user by email:

        iex> user = MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> %MyApp.UserAccounts.User{id: 1, email: "me@test.com", ...}

    The user is now available in the cache for subsequent calls. Now, let's
    suppose we update the user's email by calling:

        iex> MyApp.UserAccounts.update_user_account(user, %{
        ...>   email: "updated@test.com", ...
        ...> })
        #=> %MyApp.UserAccounts.User{id: 1, email: "updated@test.com", ...}

    The `update_user_account` function evicts the user schema stored under
    the `user.id` key (it is decorated with `cache_evict`) but not the
    reference stored under `"me@test.com"`. Next, something re-caches the
    user under its ID, for example a lookup by ID:

        iex> MyApp.UserAccounts.get_user_account(1)
        #=> %MyApp.UserAccounts.User{id: 1, email: "updated@test.com", ...}

    The old reference now points at a fresh entry again. (Without this step
    the reference would point at a missing entry, and the decorator would run
    the function body instead.) If we call `get_user_account_by_email` with
    the old email, the decorator follows the reference and returns the user
    with the updated email:

        iex> user = MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> %MyApp.UserAccounts.User{id: 1, email: "updated@test.com", ...}

    This is inconsistent: we asked for the user with email `"me@test.com"`
    and got a user with a different email, `"updated@test.com"`. The fix is
    a `:match` function:

        @decorate cacheable(
                    key: email,
                    references: &(&1 && &1.id),
                    match: &match(&1, email)
                  )
        def get_user_account_by_email(email) do
          # your logic ...
        end

        defp match(%{email: email}, email), do: true
        defp match(_, _), do: false

    Now the `cacheable` decorator caches the user only if the email matches
    the argument. Otherwise nothing is cached and the function body runs.
    With this fix, the previous call gives:

        iex> MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> nil

    Because the email does not match, the decorator removes the stale
    reference from the cache and runs the function body; assuming it uses
    `MyApp.Repo.get_by/2`, it returns `nil` because there is no such user in
    the database.

    > #### `:match` option {: .info}
    >
    > Use the `:match` option together with references so the decorator can
    > remove stale references on its own.

    ### External referenced keys

    So far the references lived in the same cache as the values. Sometimes
    you want a reference to point at a key in a different cache. Two common
    reasons:

      * You have a Redis cache and want to reduce the calls to Redis. Store
        the references in a local cache and the values in Redis; then Redis is
        hit only for the actual values, and the references are resolved
        locally.

      * You want the references in their own cache (preferably local) so you
        can give them a different eviction or garbage collection policy, for
        example expiring them more often to avoid dangling keys, since the
        `cache_evict` decorator removes only the given key (or keys), not the
        references. See the
        ["Eviction of references"](#cache_evict/3-eviction-of-references)
        section below.

    Let us modify the previous _"user accounts"_ example based on the Redis
    scenario:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching

          alias MyApp.{LocalCache, RedisCache}

          @decorate cacheable(cache: RedisCache, key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(
                      cache: LocalCache,
                      key: email,
                      references: &(&1 && keyref(&1.id, cache: RedisCache))
                    )
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(
                      cache: LocalCache,
                      key: token,
                      references: &(&1 && keyref(&1.id, cache: RedisCache))
                    )
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(cache: RedisCache, key: user.id)
          def update_user_account(user) do
            # your logic ...
          end
        end

    The functions `get_user_account/1` and `update_user_account/1` use
    `RedisCache` to store the real value in Redis while
    `get_user_account_by_email/1` and `get_user_account_by_token/1` use
    `LocalCache` to store the references. The option
    `references: &(&1 && keyref(&1.id, cache: RedisCache))` tells the
    `cacheable` decorator that the referenced key `&1.id` lives in
    `RedisCache`; the [`keyref/2`](`Nebulex.Caching.keyref/2`) macro builds
    the reference tuple for it.

    """
    @doc group: "Decorator API"
    def cacheable(attrs \\ [], block, context) do
      caching_action(:cacheable, attrs, block, context)
    end

    @doc """
    Decorator indicating that a function triggers a cache evict operation
    (`delete` or `delete_all`).

    > #### **Write-through** pattern {: .info}
    >
    > The `cache_evict` decorator fits the write-through pattern. Your function
    > writes the data to the system of record (SoR), and the decorator does the
    > rest. Unlike `cache_put`, the data is deleted from the cache instead of
    > updated.

    ## Options

    #{Nebulex.Caching.Options.cache_evict_options_docs()}

    See the ["Shared options"](#module-shared-options) section in the module
    documentation for more options.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cache_evict(key: id)
          def delete(id) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(key: {:in, [object.name, object.id]})
          def delete_object(object) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(all_entries: true)
          def delete_all do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(key: user_id, query: &query_for_user_sessions/1)
          def logout_user(user_id) do
            # Evicts both the user entry and all their session entries
            # your logic (maybe write/delete data to the SoR)
          end

          def query_for_user_sessions(%{args: [user_id]}) do
            # Return a query that matches user sessions
            # (implementation depends on your adapter)
          end
        end

    > #### Learn more {: .tip}
    >
    > For more examples and adapter-specific features (query helpers, entry
    > tagging, reference management), see the
    > [Declarative Caching Guide](declarative-caching.html).

    ## Eviction with a query

    The `:query` option takes a query (or a function that returns one at
    runtime) and evicts every entry that matches it. The query must be
    supported by the cache adapter.

    > #### Query syntax varies by adapter {: .warning}
    >
    > The query syntax and format depend on the cache adapter being used.
    > The examples in this section assume you are using the
    > `Nebulex.Adapters.Local` adapter, which uses ETS match specifications.
    > If you're using a different adapter (e.g., Redis, Partitioned, etc.),
    > consult that adapter's documentation for the appropriate query format.

    For example, say `delete_objects_by_tag` receives a `tag` and deletes all
    records with that tag from the system of record (SoR). You want those
    entries gone from the cache too, so you evict them with a query. Writing
    the query inline in the decorator gets long, so use a function that
    receives the decorator context and returns the query:

        @decorate cache_evict(query: &query_for_tag/1)
        def delete_objects_by_tag(tag) do
          # your logic to delete data from the SoR
        end

        defp query_for_tag(%{args: [tag]} = _context) do
          # Assuming we are using the `Nebulex.Adapters.Local` adapter and the
          # cached entry value is a map with a `tag` field, the match spec
          # would look like this:
          [
            {
              {:entry, :"$1", %{tag: :"$2"}, :_, :_, :_},
              [{:"=:=", :"$2", tag}],
              [true]
            }
          ]
        end

    ### More examples

    #### Evicting entries by user ID

    If you need to evict all cached entries associated with a specific user:

        @decorate cache_evict(query: &query_for_user/1)
        def delete_user_data(user_id) do
          # your logic to delete user data from the SoR
        end

        defp query_for_user(%{args: [user_id]} = _context) do
          [
            {
              {:entry, :"$1", %{user_id: :"$2"}, :_, :_, :_},
              [{:"=:=", :"$2", user_id}],
              [true]
            }
          ]
        end

    #### Evicting entries with multiple criteria

    You can build more complex queries that match multiple conditions:

        @decorate cache_evict(query: &query_for_category_and_status/1)
        def delete_products(category, status) do
          # your logic to delete products from the SoR
        end

        defp query_for_category_and_status(%{args: [category, status]}) do
          [
            {
              {:entry, :"$1", %{category: :"$2", status: :"$3"}, :_, :_, :_},
              [{:andalso, {:"=:=", :"$2", category}, {:"=:=", :"$3", status}}],
              [true]
            }
          ]
        end

    #### Direct query without a function

    For simpler cases, you can provide the query directly:

        @decorate cache_evict(
          query: [
            {
              {:entry, :"$1", %{archived: true}, :_, :_, :_},
              [],
              [true]
            }
          ]
        )
        def cleanup_archived_entries do
          # your logic to cleanup archived data from the SoR
        end

    A function is still the better choice when the query depends on the
    function arguments.

    ### Combining `:key` and `:query`

    You can use `:key` and `:query` together to evict specific entries and
    the entries matching a query. When both are given, the decorator evicts in
    this order:

    1. Query-based eviction: entries matching the query are evicted first.
    2. Key-based eviction: then the given key (or keys).

    Use it to evict a main entry along with related entries. For example, when
    logging out a user you may want to evict the user's entry and all their
    session entries (the examples below assume the `Nebulex.Adapters.Local`
    adapter):

        @decorate cache_evict(key: user_id, query: &query_for_user_sessions/1)
        def logout_user(user_id) do
          # Evicts the user entry and all session entries for this user
          UserSessions.delete_all_for_user(user_id)
        end

        defp query_for_user_sessions(%{args: [user_id]} = _context) do
          # Return a query that matches all session entries for the given user
          [
            {
              {:entry, :"$1", %{user_id: :"$2", type: "session"}, :_, :_, :_},
              [{:"=:=", :"$2", user_id}],
              [true]
            }
          ]
        end

    Another common use case is evicting multiple specific keys along with a
    query:

        @decorate cache_evict(
          key: {:in, [category.id, category.slug]},
          query: &query_for_category_products/1
        )
        def delete_category(category) do
          # Evicts both category cache entries (by id and slug) and all
          # product entries within that category
          Products.delete_all_for_category(category.id)
        end

        defp query_for_category_products(%{args: [category]} = _context) do
          [
            {
              {:entry, :"$1", %{category_id: :"$2"}, :_, :_, :_},
              [{:"=:=", :"$2", category.id}],
              [true]
            }
          ]
        end

    ### Best Practices

    - Keep query logic in separate functions so it can be reused and read on
      its own.
    - Test queries on their own before using them in decorators, to check they
      match the entries you expect.
    - Document what each query matches.
    - Mind the cost on large caches; some queries scan the whole cache.
    - Use both `:key` and `:query` for hierarchical data, where a parent entry
      and its children must go together.

    ## Eviction of references

    The `cache_evict` decorator removes only the entry for the given key (or
    keys). References to that key (created by the `:references` option of
    `cacheable`) are not removed, so they become dangling keys. There are
    several ways to evict references and avoid this:

    > #### See also {: .tip}
    >
    > For more examples, see the "Advanced Reference Cleanup with Tags and
    > Queries" section in the
    > [Declarative Caching Guide](declarative-caching.html).

      * **Specify the key and its references explicitly** - Use the
        `key: {:in, keys}` option to specify both a key and its references.
        For example, if you have:

        ```elixir
        @decorate cacheable(key: email, references: &(&1 && &1.id))
        def get_user_by_email(email) do
          # get the user from the database ...
        end
        ```

        The eviction may look like this:

        ```elixir
        @decorate cache_evict(key: {:in, [user.id, user.email]})
        def delete_user(user) do
          # delete the user from the database ...
        end
        ```

        However, to make this work, you need access to both the key and
        references in the function arguments, which is not always possible.
        Consider the previous example: what if the `delete_user` function
        receives only the ID? You won't be able to evict the reference since
        you don't have access to the email in the arguments.

      * **Set a TTL for the reference** - Configure a time-to-live value so
        references expire automatically. For example:

        ```elixir
        @decorate cacheable(
                    key: email,
                    references: &(&1 && &1.id),
                    opts: [ttl: @ttl]
                  )
        def get_user_by_email(email) do
          # get the user from the database ...
        end
        ```

        You can also specify a different TTL for the referenced key:

        ```elixir
        @decorate cacheable(
                    key: email,
                    references: &(&1 && keyref(&1.id, ttl: @another_ttl)),
                    opts: [ttl: @ttl]
                  )
        def get_user_by_email(email) do
          # get the user from the database ...
        end
        ```

      * **Use a separate cache for references** - Maintain a dedicated cache
        for references only (e.g., a cache using the local adapter). This
        allows you to provide a different eviction or garbage collection
        configuration to run the GC more frequently and keep the references
        cache clean. See the
        ["External referenced keys"](#cacheable/3-external-referenced-keys)
        section below.

      * **Combine multiple strategies** - The approaches above can be
        combined:

        - Use `key: {:in, keys}` together with a TTL configuration to
          explicitly evict keys when possible while having automatic cleanup
          as a fallback.

        - Use a separate cache for references with its own TTL and eviction
          configuration, then explicitly evict keys from both caches when
          you have access to all necessary arguments.

        This way you get automatic cleanup through TTL expiration plus
        explicit eviction whenever the function arguments give you all the
        keys.

    ### Local Adapter: Advanced Reference Eviction

    The `Nebulex.Adapters.Local` adapter has two ways to clean up references
    automatically using QueryHelper, without naming each reference key.

    #### Strategy 1: Tag-based reference grouping

    Tag the main entries and their references with the same tag, then evict
    every entry with that tag in one operation. A tag is set when the entry
    is written, so it can only come from the function arguments or a
    constant; a lookup by email cannot tag its entry with the user ID. Use a
    group tag for bulk cleanup:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache
          use Nebulex.Adapters.Local.QueryHelper

          @decorate cacheable(key: id, opts: [tag: :users])
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(
                      key: email,
                      references: &(&1 && &1.id),
                      opts: [tag: :users]
                    )
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cache_evict(query: &evict_all_users/1)
          def reload_user_accounts do
            # reload the users from the source of record ...
          end

          defp evict_all_users(_context) do
            match_spec tag: t, where: t == :users, select: true
          end
        end

    To evict a single user and its references, use Strategy 2.

    #### Strategy 2: Direct reference queries with keyref_match_spec

    Evict the main key explicitly and use `keyref_match_spec/2` to find and
    remove all associated references in the same operation:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache
          use Nebulex.Adapters.Local.QueryHelper

          @decorate cacheable(key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(key: email, references: &(&1 && &1.id))
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(key: token, references: &(&1 && &1.id))
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(key: user.id, query: &evict_user_refs/1)
          def delete_user(user) do
            # delete the user from the database ...
          end

          defp evict_user_refs(%{args: [user]}) do
            keyref_match_spec(user.id)
          end
        end

    Both clean up all references without naming each one. Choose based on
    your needs:

      * **Tag-based**: Best when you control how references are created.
        Requires planning the tags up front.
      * **Query-based**: Better when references are created by different
        decorators or only under some conditions.

    For more details on QueryHelper and available query builders, see the
    [`Nebulex.Adapters.Local.QueryHelper`](https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.QueryHelper.html)
    documentation.

    ## Eviction of external references

    As described in the `cacheable` decorator's
    ["External referenced keys"][ext-refs] section, an external reference is
    a reference that lives in another cache, for example when one cache holds
    only references and another holds the values. To evict both the value and
    its references, use `{:in, keys}` in the `:key` option and add the
    references to the list. For example:

    [ext-refs]: #cacheable/3-external-referenced-keys

        @decorate cache_evict(
                    key: {:in, [user.id, keyref(user.email, cache: ExtCache)]}
                  )
        def delete_user(user) do
          # your logic to delete data from the SoR
        end

    Assuming there is a reference under the key `user.email` in `ExtCache`,
    the decorator will remove the cached value under the key `user.id` and
    the reference under the key `user.email` from `ExtCache`.
    """
    @doc group: "Decorator API"
    def cache_evict(attrs \\ [], block, context) do
      caching_action(:cache_evict, attrs, block, context)
    end

    @doc """
    Decorator indicating that a function triggers a
    [cache put](`c:Nebulex.Cache.put/3`) operation.

    Unlike [`cacheable`](`cacheable/3`), this decorator never skips the
    function. The function always runs, and its result is stored in the cache
    when the `:match` option says so.

    > #### **Write-through** pattern {: .info}
    >
    > The `cache_put` decorator implements the write-through pattern. Your
    > function writes the data to the system of record (SoR), and the
    > decorator does the rest.

    ## Use Cases

    Use `cache_put` when:

      * **Updating data** - After writing changes to the SoR, put the new
        value in the cache.
      * **Write-through caching** - Keep the cache in sync with the SoR by
        updating it after each successful write.

    ## Key Differences from `cacheable`

    | Aspect | `cacheable` | `cache_put` |
    |--------|-------------|------------|
    | **Function execution** | Skipped on cache hit | Always executes |
    | **Cache usage** | Read-through (cache-aside) | Write-through |
    | **Best for** | Retrieving/reading data | Updating/writing data |
    | **Match function** | Determines if result should be cached | Determines if result should be cached |

    ## Options

    See the ["Shared options"](#module-shared-options) section in the module
    documentation for more options.

    ## Match Function Behavior

    The `:match` option controls when results are cached. The match function
    can return:

      * **`true`** - Cache the result as-is.
      * **`false`** - Don't cache anything.
      * **`{true, value}`** - Cache the modified `value` instead of the
        function result.
      * **`{true, value, opts}`** - Cache the `value` with additional cache
        options (e.g., different TTL).

    Use it to:

      * Cache only successful results (e.g., `{:ok, result}`)
      * Change what gets cached
      * Set different cache options depending on the result

    ## Examples

    ### Basic Cache Update

    Always execute and cache the result:

        @decorate cache_put(key: id, opts: [ttl: :timer.hours(1)])
        def update_product(id, attrs) do
          Product
          |> Repo.get!(id)
          |> Product.changeset(attrs)
          |> Repo.update()
        end

    ### Conditional Caching

    Only cache successful operations:

        @decorate cache_put(
                    key: id,
                    match: &match_ok/1,
                    opts: [ttl: :timer.hours(1)]
                  )
        def update_product(id, attrs) do
          Repo.get(Product, id)
          |> Product.changeset(attrs)
          |> Repo.update()
        end

        defp match_ok({:ok, product}), do: {true, product}
        defp match_ok({:error, _}), do: false

    ### Multiple Keys

    Update the cache with multiple keys (e.g., by ID and slug):

        @decorate cache_put(
                    key: {:in, [product.id, product.slug]},
                    match: &match_ok/1,
                    opts: [ttl: :timer.hours(1)]
                  )
        def update_product(product, attrs) do
          product
          |> Product.changeset(attrs)
          |> Repo.update()
        end

        defp match_ok({:ok, product}), do: {true, product}
        defp match_ok({:error, _}), do: false

    ### Transform Before Caching

    Use the match function to transform what gets cached:

        @decorate cache_put(
                    key: id,
                    match: &extract_result/1,
                    opts: [ttl: :timer.hours(1)]
                  )
        def fetch_and_cache(id) do
          case external_api.fetch(id) do
            {:ok, data} -> data
            {:error, reason} -> {:error, reason}
          end
        end

        # Extract and cache only the data, not the error
        defp extract_result({:error, _}), do: false
        defp extract_result(data), do: {true, data}

    ### Different TTL Based on Result

    Apply different cache durations based on the result:

        @decorate cache_put(
                    key: id,
                    match: &__MODULE__.match_with_ttl/1,
                    opts: [ttl: :timer.hours(1)]
                  )
        def fetch_data(id) do
          case external_api.fetch(id) do
            {:ok, data} -> data
            {:error, _reason} = error -> error
          end
        end

        # Cache errors for a shorter time (5 minutes)
        def match_with_ttl({:error, _reason}) do
          {true, nil, [ttl: :timer.minutes(5)]}
        end

        # Cache success for longer (1 hour, from opts)
        def match_with_ttl(data) do
          {true, data}
        end

    ## See Also

    For more examples, see the
    [Declarative Caching Guide](declarative-caching.html).
    """
    @doc group: "Decorator API"
    def cache_put(attrs \\ [], block, context) do
      caching_action(:cache_put, attrs, block, context)
    end

    ## Decorator helpers

    @doc """
    A helper function to create a reserved tuple for a dynamic cache.

    The first argument, `cache`, specifies the defined cache module,
    and the second argument, `name`, is the actual name of the cache.

    When creating a dynamic cache tuple form, use the macro
    `Nebulex.Caching.dynamic_cache/2` instead.

    ## Example

        defmodule MyApp.Books do
          use Nebulex.Caching

          @decorate cacheable(cache: dynamic_cache(MyApp.Cache, :books))
          def find_book(isbn) do
            # your logic ...
          end
        end

    """
    @doc group: "Decorator Helpers"
    @spec dynamic_cache_spec(module(), atom() | pid()) :: dynamic_cache()
    def dynamic_cache_spec(cache, name) do
      dynamic_cache(cache: cache, name: name)
    end

    @doc """
    A helper function to create a reserved tuple for a reference.

    ## Arguments

      * `cache` - The cache where the referenced key is stored. If it is `nil`,
        the referenced key is looked up in the same cache provided via the
        `:cache` option.
      * `key` - The referenced key.
      * `ttl` - The TTL for the referenced key. If configured, it overrides the
        TTL given in the decorator's option `:opts`.

    When creating a reference tuple form, use the macro
    `Nebulex.Caching.keyref/2` instead.

    See the ["Referenced keys"](#cacheable/3-referenced-keys) section in the
    `cacheable` decorator for more information.
    """
    @doc group: "Decorator Helpers"
    @spec keyref_spec(cache() | nil, any(), timeout() | nil) :: keyref_spec()
    def keyref_spec(cache, key, ttl) do
      keyref(cache: cache, key: key, ttl: ttl)
    end

    @doc """
    Default match function.
    """
    @doc group: "Decorator Helpers"
    @spec default_match(any()) :: boolean()
    def default_match(result)

    def default_match({:error, _}), do: false
    def default_match(:error), do: false
    def default_match(nil), do: false
    def default_match(_other), do: true

    @doc """
    Default key generation function.
    """
    @doc group: "Decorator Helpers"
    @spec generate_key(context()) :: any()
    def generate_key(context)

    def generate_key(%{args: []}), do: 0
    def generate_key(%{args: [arg]}), do: arg
    def generate_key(%{args: args}), do: :erlang.phash2(args)

    ## Private functions for decorators

    defp caching_action(decorator, attrs, block, context) do
      # Get options defined via the __using__ macro
      use_opts = Module.get_attribute(context.module, :__caching_opts__, [])

      # Build decorator context
      context = decorator_context(decorator, context)

      # Resolve the cache to use
      cache_var = get_cache(attrs, use_opts)

      # Build key generation block
      keygen_block = keygen_block(decorator, attrs, use_opts)

      # Get the options to be given to the cache commands
      opts_var = Keyword.get_lazy(attrs, :opts, fn -> Keyword.fetch!(use_opts, :opts) end)

      # Get the on error option
      on_error = on_error_opt(attrs, fn -> Keyword.fetch!(use_opts, :on_error) end)

      # Get the transaction option
      txn_enabled? = get_boolean(attrs, :transaction) || get_boolean(use_opts, :transaction)

      # Build the action block
      action_block =
        action_block(
          decorator,
          block,
          attrs,
          keygen_block,
          on_error,
          Keyword.get_lazy(attrs, :match, fn ->
            Keyword.get(use_opts, :match, &__MODULE__.default_match/1)
          end)
        )
        |> maybe_add_txn_wrapper(attrs, keygen_block, on_error, txn_enabled?)

      quote do
        # Set common vars
        cache = unquote(cache_var)
        opts = unquote(opts_var)

        # Push the decorator context onto the stack
        _ignore = Context.push(unquote(context))

        try do
          # Execute the decorated function's code block
          unquote(action_block)
        after
          # Pop the decorator context from the stack
          _ignore = Context.pop()
        end
      end
    end

    defp decorator_context(decorator, context) do
      # Sanitize context args
      args =
        context.args
        |> Enum.reduce([], &sanitize_arg/2)
        |> Enum.reverse()

      quote do
        var!(ctx_args, __MODULE__) = unquote(args)

        %Context{
          decorator: unquote(decorator),
          module: unquote(context.module),
          function_name: unquote(context.name),
          arity: unquote(context.arity),
          args: var!(ctx_args, __MODULE__)
        }
      end
    end

    defp sanitize_arg({:\\, _, [ast, _]}, acc) do
      sanitize_arg(ast, acc)
    end

    defp sanitize_arg({:=, _, [_, ast]}, acc) do
      sanitize_arg(ast, acc)
    end

    defp sanitize_arg({var, _meta, context} = ast, acc) when is_atom(var) and is_atom(context) do
      if match?("_" <> _, "#{var}") or Macro.special_form?(var, 0) do
        acc
      else
        [ast | acc]
      end
    end

    defp sanitize_arg(_ast, acc) do
      acc
    end

    defp get_cache(attrs, use_opts) do
      with :error <- Keyword.fetch(attrs, :cache),
           :error <- Keyword.fetch(use_opts, :cache) do
        opts =
          use_opts
          |> Keyword.merge(attrs)
          |> Keyword.keys()

        raise ArgumentError, "required :cache option not found, received options: #{inspect(opts)}"
      else
        {:ok, cache} -> cache
      end
    end

    defp keygen_block(decorator, attrs, use_opts) do
      case {Keyword.fetch(attrs, :key), decorator} do
        {{:ok, {:in, _keys}}, :cacheable} ->
          raise ArgumentError,
                "invalid value for :key option: {:in, [...]} is not " <>
                  "supported for cacheable decorator"

        {{:ok, {:in, [_ | _]} = key}, _} ->
          quote(do: unquote(key))

        {{:ok, {:in, keys}}, _} ->
          raise ArgumentError,
                "invalid value for :key option: {:in, keys} expects keys " <>
                  "to be a non empty list, got: #{inspect(keys)}"

        {{:ok, key}, _} ->
          quote(do: unquote(key))

        {:error, _} ->
          generator = Keyword.get(use_opts, :default_key_generator, &__MODULE__.generate_key/1)

          quote(do: unquote(generator))
      end
    end

    defp action_block(:cacheable, block, attrs, keygen, on_error, match) do
      references = Keyword.get(attrs, :references)

      quote do
        Runtime.eval_cacheable(
          cache,
          unquote(keygen),
          unquote(references),
          opts,
          unquote(match),
          unquote(on_error),
          fn -> unquote(block) end
        )
      end
    end

    defp action_block(:cache_put, block, _attrs, keygen, on_error, match) do
      quote do
        result = unquote(block)

        Runtime.eval_cache_put(
          cache,
          unquote(keygen),
          result,
          opts,
          unquote(on_error),
          unquote(match)
        )

        result
      end
    end

    defp action_block(:cache_evict, block, attrs, keygen, on_error, _match) do
      before_invocation? = get_boolean(attrs, :before_invocation)
      all_entries? = get_boolean(attrs, :all_entries)
      key = cache_evict_key(attrs, keygen)

      quote do
        Runtime.eval_cache_evict(
          cache,
          unquote(key),
          opts,
          unquote(before_invocation?),
          unquote(all_entries?),
          unquote(on_error),
          fn -> unquote(block) end
        )
      end
    end

    defp cache_evict_key(attrs, keygen) do
      case {Keyword.fetch(attrs, :query), Keyword.fetch(attrs, :key)} do
        {{:ok, q}, {:ok, _k}} -> quote(do: {:"$nbx_query", unquote(q), unquote(keygen)})
        {{:ok, q}, :error} -> quote(do: {:"$nbx_query", unquote(q)})
        _else -> keygen
      end
    end

    defp maybe_add_txn_wrapper(block, _attrs, _keygen, _on_error, false) do
      quote do
        unquote(block)
      end
    end

    defp maybe_add_txn_wrapper(block, attrs, keygen, on_error, true) do
      key = cache_evict_key(attrs, keygen)

      quote do
        context = Context.get()
        cache = Runtime.eval_cache(cache, context)
        key = Runtime.eval_key(unquote(key), context)
        txn_keys = Runtime.txn_keys(key)

        result =
          Runtime.run_cmd(
            cache,
            :transaction,
            [fn -> unquote(block) end, [keys: txn_keys]],
            unquote(on_error)
          )

        with {:ok, result} <- result do
          result
        end
      end
    end

    defp on_error_opt(attrs, default) do
      get_option(attrs, :on_error, ":raise or :nothing", &(&1 in [:raise, :nothing]), default)
    end

    defp get_boolean(attrs, key) do
      get_option(attrs, key, "a boolean", &Kernel.is_boolean/1, false)
    end
  end
end
