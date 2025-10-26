if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Caching.Decorators do
    @moduledoc """
    Declarative decorator-based caching, inspired by
    [Spring Cache Abstraction][spring-cache].

    > *[`decorator`][decorator-lib] library is used underneath.*

    [spring-cache]: https://docs.spring.io/spring/docs/3.2.x/spring-framework-reference/html/cache.html
    [decorator-lib]: https://github.com/arjan/decorator

    For caching declaration, the abstraction provides three Elixir function
    decorators: `cacheable `, `cache_evict`, and `cache_put`, which allow
    functions to trigger cache population or cache eviction.
    Let us take a closer look at each decorator.

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

    The cache abstraction allows not just the population of a cache store but
    also eviction. This process is useful for removing stale or unused data from
    the cache. Opposed to `cacheable`, the decorator `cache_evict` demarcates
    functions that perform cache eviction, which are functions that act as
    triggers for removing data from the cache. Just like its sibling,
    `cache_evict` requires specifying the cache that will be affected by the
    action, allows to provide a key or a list of keys to be evicted, but in
    addition, features an extra option `:all_entries` which indicates whether
    a cache-wide eviction needs to be performed rather than just one or a few
    entries (based on `:key` or `:keys` option):

        @decorate cache_evict(cache: Cache, all_entries: true)
        def load_books(file_stream) do
          # the logic for loading books ...
        end

    The option `:all_entries` comes in handy when an entire cache region needs
    to be cleared out - rather than evicting each entry (which would take a
    long time since it is inefficient), all the entries are removed in one
    operation as shown above.

    One can also indicate whether the eviction should occur after (the default)
    or before the function executes through the `:before_invocation` attribute.
    The former provides the same semantics as the rest of the decorators; once
    the method completes successfully, an action (in this case, eviction) on the
    cache is executed. If the function does not execute (as it might be cached)
    or an exception is raised, the eviction does not occur. The latter
    (`before_invocation: true`) causes the eviction to occur always before the
    method is invoked. This is useful in cases where the eviction does not need
    to be tied to the function execution outcome.

    See `cache_evict/3` for more information.

    ## Shared Options

    All three cache decorators explained previously accept the following
    options:

    #{Nebulex.Caching.Options.shared_options_docs()}

    ## Cache configuration

    As documented in the options above, the `:cache` option configures the cache
    for the decorated function (in the decorator declaration). However, there
    are three possible values, such as documented in the `t:cache/0` type.
    Let's go over these cache value alternatives in detail.

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

    > See ["Dynamic caches"][dynamic-caches] for more information.

    [dynamic-caches]: http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Cache.html#module-dynamic-caches

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

    While option `:cache` is handy for specifying the decorated function's
    cache, it may be cumbersome when there is a module with several decorated
    functions, and all use the same cache. In that case, we must set the
    `:cache` option with the same value in all the decorated functions.
    Fortunately, the `:cache` option can be configured globally for all
    decorated functions in a module when defining the caching usage via
    `use Nebulex.Caching`. For example:

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

    In the snippet above, the function `get_book/1` is associated with the
    cache `MyApp.Cache` by default since option `:cache` is not provided in
    the decorator. In other words, when the `:cache` option is configured
    globally (when defining the caching usage via `use Nebulex.Caching`),
    it is not required in the decorator declaration. However, one can always
    override the global or default cache in the decorator declaration by
    providing the option `:cache`, as is shown in the `best_sellers/0`
    function, which is associated with a different cache.

    To conclude, it is crucial to know the decorator must be associated with
    a cache, either a global or default cache defined at the caching usage
    definition (e.g., `use Nebulex.Caching, cache: MyCache`) or a specific
    one configured in the decorator declaration.

    ## Key Generation

    Since caches are essentially key-value stores, each invocation of a cached
    function needs to be translated into a suitable key for cache access. The
    key can be generated using a default key generator (which is configurable)
    or through decorator options `:key` or `:keys`. Let us take a closer look
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
            cache: MyApp.Cache
            default_key_generator: &MyApp.Keygen.generate/1

          ...
        end

    The function given to `:default_key_generator` must follow the format
    `&Mod.fun/arity`.

    ### Custom Key Generation Declaration

    Since caching is generic, it is quite likely the target functions have
    various signatures that cannot be simply mapped on top of the cache
    structure. This tends to become obvious when the target function has
    multiple arguments out of which only some are suitable for caching
    (while the rest are used only by the function logic). For example:

        @decorate cacheable(cache: Cache)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    At first glance, while the two `boolean` arguments influence the way the
    book is found, they are not used for the cache. Furthermore, what if only
    one of the two is important while the other is not?

    For such cases, the `cacheable` decorator allows the user to specify how
    the key is generated through the `:key` option (the same applies to all
    decorators). The developer can pick the arguments of interest (or their
    nested properties), perform operations or even invoke arbitrary functions
    without having to write any code or implement any interface. This is the
    recommended approach over the default generator since functions tend to be
    quite different in signatures as the code base grows; while the default
    strategy might work for some functions, it rarely does for all functions.

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
    is like the decorator was applied to all function clauses separately.
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

    Some options (`:cache`, `:key`, `:references`, `:match`) may be configured
    with anonymous functions. These functions are **inlined by the decorator
    macro** at compile time and **evaluated at runtime** each time the decorated
    function is invoked. In other words, on every decorated call a new function
    term is created and executed once (or a few times) by the decorator.

    This behavior is normal and efficient for most cases, but understanding how
    it works helps you write clearer and faster code.

    ### Key points

      * Both anonymous functions (`fn ... end`) and module captures
        (`&Mod.fun/2`) allocate a new function term per invocation.

      * A **module capture** (`&Mod.fun/arity`) has **no environment** —
        it doesn’t carry any extra data, so its allocation is minimal.

      * An **anonymous closure** may **capture variables** from its environment.
        If the captured data is large (e.g. big maps, structs, lists, configs),
        every decorated call will create a new closure holding references to
        those values, which can add GC pressure on hot paths.

    ### Best practices

      * Small lambdas are perfectly fine and idiomatic:

        ```elixir
        key: &(&1 && &1.id)
        references: &(&1 && keyref(&1.id, cache: RedisCache))
        match: &match(&1, email)
        ```

      * Prefer **module captures** for shared or non-trivial logic. They allocate
        a fresh but **environment-free** function per call, which is very cheap:

        ```elixir
        key: &MyApp.Keygen.generate/1
        match: &__MODULE__.match_fun/2
        ```

      * If you need access to the function arguments, use the
        **decorator context** instead of capturing:

        ```elixir
        def match_fun(result, %Nebulex.Caching.Decorators.Context{args: [arg]}) do
          check_valid?(result, arg)
        end

        @decorate cacheable(key: arg.id, match: &__MODULE__.match_fun/2)
        def get_user(arg), do: Repo.get(User, arg.id)
        ```

      * Capturing a small or static module attribute (e.g. `@config`) inside the
        lambda is perfectly fine. The value is referenced from the environment,
        not duplicated:

        ```elixir
        # Small config map
        @config %{foo: "bar", baz: "qux"}

        @decorate cacheable(key: id, match: &check_valid?(&1, @config))
        def get_user(id), do: Repo.get(User, id)
        ```

      * If you do use lambdas, **keep captured data small**. Instead of closing
        over large maps or configs, **fetch what you need inside a module
        function**:

        ```elixir
        # ❌ Avoid: capturing the full config (large map) in the lambda
        @config %{ttl: :timer.hours(1), cache: MyApp.Cache, extra: %{...}}

        @decorate cacheable(key: id, match: &MyApp.Validator.valid?(&1, @config))
        def get_user(id), do: Repo.get(User, id)

        # ✅ Better: fetch what you need inside the module function
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

    Because Nebulex decorators run as often as your cached functions are called,
    the option lambdas are evaluated on every call. However, the cost of
    creating a small or environment-free function term per call is negligible
    in most real-world scenarios.

    You only need to be mindful of this if:

      * The function captures **large data structures** in its environment.
      * Profiling shows decorator evaluation as a measurable hotspot.

    When in doubt, use a **module capture** for clarity and consistency — it's
    the simplest, most allocation-friendly choice.

    ## Error Handling Strategies

    The `:on_error` option controls how decorators behave when cache operations
    fail (e.g., connection lost, memory exhausted, etc.). It does NOT apply to
    errors from your business logic; only to cache infrastructure errors.

    ### `:on_error` with `cacheable`

    **Option 1: `:nothing` (default)** - Graceful degradation

    When a cache error occurs, the function still executes and returns its result
    (just without caching). Perfect for non-critical caches where cache failures
    shouldn't affect application functionality.

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

    **Option 2: `:raise`** - Strict consistency

    When a cache error occurs, an exception is raised. Useful for critical
    caches where failures should be visible and prevent application flow.

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

    **`:nothing`** - Ignores cache errors, function result still returned

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

      * [Cache Usage Patterns Guide](http://hexdocs.pm/nebulex/3.0.0-rc.2/cache-usage-patterns.html).
      * [Declarative Caching Guide](declarative-caching.html).

    """

    defmodule Context do
      @moduledoc """
      Decorator context.
      """

      @typedoc """
      Decorator context type.

      The decorator context defines the following keys:

        * `:decorator` - Decorator's name.
        * `:module` - The invoked module.
        * `:function_name` - The invoked function name
        * `:arity` - The arity of the invoked function.
        * `:args` - The arguments that are given to the invoked function.

      ## Caveats about the `:args`

      The following are some caveats about the context's `:args`
      to keep in mind:

        * Only arguments explicitly assigned to a variable will be included.
        * Ignored or underscored arguments will be ignored.
        * Pattern-matching expressions without a variable assignment will be
          ignored. Therefore, if there is a pattern-matching and you want to
          include its value, it has to be explicitly assigned to a variable.

      For example, suppose you have a module with a decorated function:

          defmodule MyApp.SomeModule do
            use Nebulex.Caching

            alias MyApp.Cache

            @decorate cacheable(cache: Cache, key: &__MODULE__.key_generator/1)
            def get_something(x, _y, _, {_, _}, [_, _], %{a: a}, %{} = z) do
              # Function's logic
            end

            def key_generator(context) do
              # Key generation logic
            end
          end

      The generator will be invoked like so:

          key_generator(%Nebulex.Caching.Decorators.Context{
            decorator: :cacheable,
            module: MyApp.SomeModule,
            function_name: :get_something,
            arity: 7,
            args: [x, z]
          })

      As you may notice, only the arguments `x` and `z` are included in the
      context args when calling the `key_generator/1` function.
      """
      @type t() :: %__MODULE__{
              decorator: :cacheable | :cache_evict | :cache_put,
              module: module(),
              function_name: atom(),
              arity: non_neg_integer(),
              args: [any()]
            }

      # Context struct
      defstruct decorator: nil, module: nil, function_name: nil, arity: 0, args: []
    end

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

    # Decorator context key
    @decorator_context_key {__MODULE__, :decorator_context}

    ## Decorator API

    @doc """
    As the name implies, the `cacheable` decorator indicates storing in cache
    the result of invoking a function.

    Each time a decorated function is invoked, the caching behavior will be
    applied, checking whether the function has already been invoked for the
    given arguments. A default algorithm uses the function arguments to compute
    the key. Still, a custom key can be provided through the `:key` option,
    or a custom key-generator function can replace the default one
    (See ["Key Generation"](#module-key-generation) section in the module
    documentation).

    If no value is found in the cache for the computed key, the target function
    will be invoked, and the returned value will be stored in the associated
    cache. Note that what is cached can be handled with the `:match` option.

    > #### **Read-through** pattern {: .info}
    >
    > The `cacheable` decorator supports the **Read-through** pattern.
    > The loader to retrieve the value from the system of record (SoR)
    > is your function's logic, and the macro under the hood provides
    > the rest.

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

    Referenced keys are handy when multiple keys keep the same value. For
    example, let's imagine we have a schema `User` with multiple unique fields,
    like `:id`, `:email`, and `:token`. We may have a module with functions
    retrieving the user account by any of those fields, like so:

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

    As you notice, all three functions will store the same user record under a
    different key. It could be more efficient in terms of memory space. Besides,
    when the user record is updated, we have to invalidate the previously cached
    entries, which means we have to specify in the `cache_evict` decorator all
    the different keys associated with the cached user account.

    Using the referenced keys, we can address it better and more simply.
    The module will look like this:

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

    With the option `:references`, we are indicating to the `cacheable`
    decorator to store the user id under the key `email` and the key `token`
    (assuming the function returns a user record), and the user record itself
    under the user id, which is the referenced key; if the function returns
    `nil`, the decorator will cache nothing. This time, instead of storing the
    same object three times, the decorator will cache it only once under the
    user ID, and the other entries will keep a reference to it. When the
    functions `get_user_account_by_email/1` or `get_user_account_by_token/1` are
    are executed, the decorator will automatically handle it; under the hood,
    it will fetch the referenced key given by `email` or `token` first, and
    then get the user record under the referenced key.

    On the other hand, in the eviction function `update_user_account/1`, since
    the user record is stored only once under the user's ID, we could set the
    option `:key` to the user's ID, without specifying multiple keys like in
    the previous case. However, there is a caveat:

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

    The `update_user_account` function should have removed the user schema
    associated with the `user.id` key (decorated with `cache_evict`) but not
    the references. Therefore, if we call `get_user_account_by_email` again,
    we will get the user with the updated email:

        iex> user = MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> %MyApp.UserAccounts.User{id: 1, email: "updated@test.com", ...}

    However, here we have an inconsistency because we are requesting a user with
    the email `"me@test.com"` and we got a user with a different email
    `"updated@test.com"` (the updated one). How can we avoid this? The answer
    is to leverage the `:match` option to ensure consistency and correctness.
    Let's provide a match function that helps us with it:

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

    With the solution above, the `cacheable` decorator only caches the user's
    value if the email matches the one in the arguments. Otherwise, nothing is
    cached, and the decorator evaluates the function's block. Previously, the
    decorator was caching the user regardless of the requested email value.
    With this fix, if we try the previous call:

        iex> MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> nil

    Since there is an email mismatch in the previous call, the decorator removes
    the mismatch reference from the cache (eliminating the inconsistency) and
    executes the function body, assuming it uses `MyApp.Repo.get_by/2`, `nil`
    is returned because there is no such user in the database.

    > #### `:match` option {: .info}
    >
    > The `:match` option can and should be used when using references to allow
    > the decorator to remove inconsistent cache key references automatically.

    ### External referenced keys

    Previously, we saw how to work with referenced keys but on the same cache,
    like "internal references." Despite this being the typical case scenario,
    there could be situations where you may want to reference a key stored in a
    different or external cache. Why would I want to reference a key located in
    a separate cache? There may be multiple reasons, but let's give a few
    examples.

      * One example is when you have a Redis cache; in such case, you likely
        want to optimize the calls to Redis as much as possible. Therefore, you
        should store the referenced keys in a local cache and the values in
        Redis. This way, we only hit Redis to access the keys with the actual
        values, and the decorator resolves the referenced keys locally.

      * Another example is for keeping the cache key references isolated,
        preferably locally. Then, apply a different eviction (or garbage
        collection) policy for the references; one may want to expire the
        references more often to avoid having dangling keys since the
        `cache_evict` decorator doesn't remove the references automatically,
        just the defined key (or keys). See the
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

    The functions `get_user_account/1` and `update_user_account/2` use
    `RedisCache` to store the real value in Redis while
    `get_user_account_by_email/1` and `get_user_account_by_token/1` use
    `LocalCache` to store the cache key references. Then, with the option
    `references: &(&1 && keyref(&1.id, cache: RedisCache))` we are telling the
    `cacheable` decorator the referenced key given by `&1.id` is located in the
    cache `RedisCache`; the macro [`keyref/2`](`Nebulex.Caching.keyref/2`)
    builds the required reference tuple for the external cache reference
    underneath.

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
    > The `cache_evict` decorator supports the **write-through** pattern. Your
    > function provides the logic to write data to the system of record (SoR),
    > and the decorator under the hood provides the rest. But in contrast with
    > the `cache_put` decorator, the data is deleted from the cache instead of
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
    > For comprehensive examples, real-world patterns, and adapter-specific
    > features (including query helpers, entry tagging, and reference
    > management), see the [Declarative Caching Guide](declarative-caching.html).

    ## Eviction with a query

    The `:query` option allows you to provide a query (or a function that
    returns a query at runtime) to evict multiple cache entries based on
    specific criteria. The query must be supported by the cache adapter.

    > #### Query syntax varies by adapter {: .warning}
    >
    > The query syntax and format depend on the cache adapter being used.
    > The examples in this section assume you are using the
    > `Nebulex.Adapters.Local` adapter, which uses ETS match specifications.
    > If you're using a different adapter (e.g., Redis, Partitioned, etc.),
    > consult that adapter's documentation for the appropriate query format.

    To explain how this works, let's use an example. Imagine you have a function
    `delete_objects_by_tag` that receives a `tag` as an argument and deletes
    all records matching the given tag from the system of record (SoR). You want
    to evict those entries from the cache as well. This can be accomplished by
    using a query to identify and evict all matching entries. However, writing
    the query directly in the decorator can be verbose and hard to maintain,
    especially for complex queries. Instead, you can use a function that
    receives the decorator context and returns the required query to evict all
    cached entries matching the given tag.

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
              {:entry, :"$1", %{tag: :"$2"}, :_, :_},
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
              {:entry, :"$1", %{user_id: :"$2"}, :_, :_},
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
              {:entry, :"$1", %{category: :"$2", status: :"$3"}, :_, :_},
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
              {:entry, :"$1", %{archived: true}, :_, :_},
              [],
              [true]
            }
          ]
        )
        def cleanup_archived_entries do
          # your logic to cleanup archived data from the SoR
        end

    However, using a function is recommended for better readability and
    maintainability, especially when the query depends on function arguments.

    ### Combining `:key` and `:query`

    You can use both `:key` and `:query` options together to evict both specific
    entries and entries matching a query pattern. When both options are provided,
    the decorator executes the eviction in the following order:

    1. **Query-based eviction** - First, entries matching the query are evicted.
    2. **Key-based eviction** - Then, the specific key(s) are evicted.

    This is useful when you need to evict a primary entry along with related
    entries. For example, when logging out a user, you might want to evict the
    user's cache entry and all their active session entries (the examples below
    assume you are using the `Nebulex.Adapters.Local` adapter):

        @decorate cache_evict(key: user_id, query: &query_for_user_sessions/1)
        def logout_user(user_id) do
          # Evicts the user entry and all session entries for this user
          UserSessions.delete_all_for_user(user_id)
        end

        defp query_for_user_sessions(%{args: [user_id]} = _context) do
          # Return a query that matches all session entries for the given user
          [
            {
              {:entry, :"$1", %{user_id: :"$2", type: "session"}, :_, :_},
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
              {:entry, :"$1", %{category_id: :"$2"}, :_, :_},
              [{:"=:=", :"$2", category.id}],
              [true]
            }
          ]
        end

    ### Best Practices

    - **Keep query logic in separate functions** for reusability and cleaner
      code.
    - **Test queries independently** before using them in decorators to ensure
      they match the expected entries.
    - **Document query behavior** and the expected match criteria for future
      maintainability.
    - **Consider performance implications** when querying large datasets, as
      some queries may require full cache scans.
    - **Use both `:key` and `:query` when evicting hierarchical data** where
      you need to remove both a parent entry and its related child entries.

    ## Eviction of references

    When the `cache_evict` decorator annotates a key (or keys) to evict, it
    removes only the entry associated with that key. Therefore, if the key has
    references (as created by the `:references` option in `cacheable`), those
    are not automatically removed, which results in dangling keys. However,
    there are multiple ways to evict references and avoid dangling keys:

    > #### See also {: .tip}
    >
    > For comprehensive real-world examples and integration patterns, see the
    > "Advanced Reference Cleanup with Tags and Queries" section in the
    > [Declarative Caching Guide](declarative-caching.html).

      * **Specify the key and its references explicitly** - Use the
        `key: {:in, keys}` option to specify both a key and its references.
        For example, if you have:

        ```elixir
        @decorate cacheable(key: email, references: & &1.id)
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

      * **Combine multiple strategies** - You can combine the previous
        approaches to create a more robust solution:

        - Use `key: {:in, keys}` together with a TTL configuration to
          explicitly evict keys when possible while having automatic cleanup
          as a fallback.

        - Use a separate cache for references with its own TTL and eviction
          configuration, then explicitly evict keys from both caches when
          you have access to all necessary arguments.

        This layered approach provides both automatic cleanup through TTL
        expiration and manual control when you have access to all the
        necessary keys in your function arguments.

    ### Local Adapter: Advanced Reference Eviction

    The `Nebulex.Adapters.Local` adapter provides powerful strategies for
    automatic reference cleanup using QueryHelper, without needing to specify
    each reference key individually.

    #### Strategy 1: Tag-based reference grouping

    Tag both the main key and its references with the same tag, then evict all
    entries with that tag in one operation:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache
          use Nebulex.Adapters.Local.QueryHelper

          @decorate cacheable(key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(
                      key: email,
                      references: &(&1 && &1.id),
                      opts: [tag: {:user, &(&1.id)}]
                    )
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cache_evict(key: user.id, query: &evict_by_user_tag/1)
          def delete_user(user) do
            # delete the user from the database ...
          end

          defp evict_by_user_tag(%{args: [user]}) do
            match_spec tag: t, where: t == {:user, user.id}
          end
        end

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

    Both strategies provide automatic cleanup of all references without manually
    specifying each reference key. Choose based on your needs:

      * **Tag-based**: Best when you control reference creation upfront and want
        a simple, declarative approach. Requires planning tags during caching.
      * **Query-based**: More flexible for cases where references may exist
        across different decorators or when references are created
        conditionally.

    For more details on QueryHelper and available query builders, see the
    [`Nebulex.Adapters.Local.QueryHelper`](https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.QueryHelper.html)
    documentation.

    ## Eviction of external references

    As mentioned in the `cacheable` decorator's
    ["External referenced keys"][ext-refs] section, an external reference is a
    key (or reference) that lives in another cache store. For example, you might
    have one cache to store only the references and another to store the actual
    values. In these cases, when you annotate the eviction function, you want to
    remove both the cached value and any references to it that may exist.
    Therefore, you can use `{:in, keys}` in the `:key` option, adding the
    references to be removed to the list. For example:

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

    In contrast to the [`cacheable`](`cacheable/3`) decorator, this decorator
    does not cause the decorated function to be skipped. Instead, it always
    causes the function to be invoked and its result to be stored in the
    associated cache if the condition given by the `:match` option matches
    accordingly.

    > #### **Write-through** pattern {: .info}
    >
    > The `cache_put` decorator supports the **write-through** pattern. Your
    > function provides the logic to write data to the system of record (SoR),
    > and the decorator under the hood provides the rest.

    ## Use Cases

    The `cache_put` decorator is ideal for scenarios where:

      * **Updating or modifying data** - After writing changes to the SoR,
        update the cache with the new value.
      * **Write-through caching** - Maintain consistency between SoR and cache
        by updating the cache after successful writes.

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

    The `:match` option is crucial for controlling when results are cached.
    The match function can return:

      * **`true`** - Cache the result as-is.
      * **`false`** - Don't cache anything.
      * **`{true, value}`** - Cache the modified `value` instead of the
        function result.
      * **`{true, value, opts}`** - Cache the `value` with additional cache
        options (e.g., different TTL).

    This is useful for:

      * Caching only successful operations (e.g., `{:ok, result}`)
      * Transforming the cached value
      * Applying different cache options based on the result

    ## Examples

    ### Basic Cache Update

    Always execute and cache the result:

        @decorate cache_put(key: id, opts: [ttl: :timer.hours(1)])
        def update_product(id, attrs) do
          product = Repo.get(Product, id)
          Repo.update(product, attrs)
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

    For real-world integration examples and comprehensive patterns, see
    the [Declarative Caching Guide](declarative-caching.html).
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

      # Build the action block
      action_block =
        action_block(
          decorator,
          block,
          attrs,
          keygen_block,
          on_error_opt(attrs, fn -> Keyword.fetch!(use_opts, :on_error) end),
          Keyword.get_lazy(attrs, :match, fn ->
            Keyword.get(use_opts, :match, &__MODULE__.default_match/1)
          end)
        )

      quote do
        # Set common vars
        cache = unquote(cache_var)
        opts = unquote(opts_var)

        # Set the decorator context
        _ = Process.put(unquote(@decorator_context_key), unquote(context))

        try do
          # Execute the decorated function's code block
          unquote(action_block)
        after
          # Reset decorator context
          Process.delete(unquote(@decorator_context_key))
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

        {{:ok, {:in, keys} = key}, _} when is_list(keys) and length(keys) > 0 ->
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
        unquote(__MODULE__).eval_cacheable(
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

        unquote(__MODULE__).eval_cache_put(
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

      key =
        case {Keyword.fetch(attrs, :query), Keyword.fetch(attrs, :key)} do
          {{:ok, q}, {:ok, _k}} -> quote(do: {:"$nbx_query", unquote(q), unquote(keygen)})
          {{:ok, q}, :error} -> quote(do: {:"$nbx_query", unquote(q)})
          _else -> keygen
        end

      quote do
        unquote(__MODULE__).eval_cache_evict(
          cache,
          unquote(key),
          unquote(before_invocation?),
          unquote(all_entries?),
          unquote(on_error),
          fn -> unquote(block) end
        )
      end
    end

    defp on_error_opt(attrs, default) do
      get_option(attrs, :on_error, ":raise or :nothing", &(&1 in [:raise, :nothing]), default)
    end

    defp get_boolean(attrs, key) do
      get_option(attrs, key, "a boolean", &Kernel.is_boolean/1, false)
    end

    ## Internal API

    @doc """
    Convenience function for wrapping and/or encapsulating
    the **cacheable** decorator logic.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec eval_cacheable(any(), any(), references(), keyword(), match(), on_error(), fun()) :: any()
    def eval_cacheable(cache, key, references, opts, match, on_error, block_fun) do
      context = Process.get(@decorator_context_key)
      cache = eval_cache(cache, context)
      key = eval_key(key, context)

      do_eval_cacheable(cache, key, references, opts, match, on_error, block_fun)
    end

    defp do_eval_cacheable(cache, key, nil, opts, match, on_error, block_fun) do
      do_apply(cache, :fetch, [key, opts])
      |> handle_cacheable(
        on_error,
        block_fun,
        &__MODULE__.eval_cache_put(cache, key, &1, opts, on_error, match)
      )
    end

    defp do_eval_cacheable(
           ref_cache,
           ref_key,
           {:"$nbx_parent_keyref", keyref(cache: cache, key: key)},
           opts,
           match,
           on_error,
           block_fun
         ) do
      do_apply(ref_cache, :fetch, [ref_key, opts])
      |> handle_cacheable(
        on_error,
        block_fun,
        fn value ->
          with false <- do_eval_cache_put(ref_cache, ref_key, value, opts, on_error, match) do
            # The match returned `false`, remove the parent's key reference
            _ = do_apply(cache, :delete, [key])

            false
          end
        end,
        fn value ->
          case eval_function(match, value) do
            false ->
              # Remove the parent's key reference
              _ = do_apply(cache, :delete, [key])

              block_fun.()

            _else ->
              value
          end
        end
      )
    end

    defp do_eval_cacheable(cache, key, references, opts, match, on_error, block_fun) do
      case do_apply(cache, :fetch, [key, opts]) do
        {:ok, keyref(cache: ref_cache, key: ref_key)} ->
          eval_cacheable(
            ref_cache || cache,
            ref_key,
            {:"$nbx_parent_keyref", keyref(cache: cache, key: key)},
            opts,
            match,
            on_error,
            block_fun
          )

        other ->
          handle_cacheable(other, on_error, block_fun, fn result ->
            with {:ok, reference} <- eval_cacheable_ref(references, result),
                 true <- eval_cache_put(cache, reference, result, opts, on_error, match) do
              :ok = cache_put(cache, key, reference, opts)
            end
          end)
      end
    end

    defp eval_cacheable_ref(references, result) do
      case eval_function(references, result) do
        nil -> :halt
        keyref() = ref -> {:ok, ref}
        referenced_key -> {:ok, keyref(key: referenced_key)}
      end
    end

    # Handle fetch result
    defp handle_cacheable(result, on_error, block_fn, key_err_fn, on_ok \\ nil)

    defp handle_cacheable({:ok, value}, _on_error, _block_fn, _key_err_fn, nil) do
      value
    end

    defp handle_cacheable({:ok, value}, _on_error, _block_fn, _key_err_fn, on_ok) do
      on_ok.(value)
    end

    defp handle_cacheable({:error, %Nebulex.KeyError{}}, _on_error, block_fn, key_err_fn, _on_ok) do
      block_fn.()
      |> tap(key_err_fn)
    end

    defp handle_cacheable({:error, _}, :nothing, block_fn, _key_err_fn, _on_ok) do
      block_fn.()
    end

    defp handle_cacheable({:error, reason}, :raise, _block_fn, _key_err_fn, _on_ok) do
      raise reason
    end

    @doc """
    Convenience function for wrapping and/or encapsulating
    the **cache_evict** decorator logic.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec eval_cache_evict(any(), any(), boolean(), boolean(), on_error(), fun()) :: any()
    def eval_cache_evict(cache, key, before?, all_entries?, on_error, block_fun) do
      context = Process.get(@decorator_context_key)
      cache = eval_cache(cache, context)
      key = eval_key(key, context)

      do_eval_cache_evict(cache, key, before?, all_entries?, on_error, block_fun)
    end

    defp do_eval_cache_evict(cache, key, true, all_entries?, on_error, block_fun) do
      _ = do_evict(all_entries?, cache, key, on_error)

      block_fun.()
    end

    defp do_eval_cache_evict(cache, key, false, all_entries?, on_error, block_fun) do
      result = block_fun.()

      _ = do_evict(all_entries?, cache, key, on_error)

      result
    end

    defp do_evict(false, cache, {:in, keys}, on_error) do
      keys
      |> group_by_cache(cache)
      |> Enum.each(fn
        {cache, [key]} ->
          run_cmd(cache, :delete, [key, []], on_error)

        {cache, keys} ->
          run_cmd(cache, :delete_all, [[in: keys]], on_error)
      end)
    end

    defp do_evict(false, cache, {:query, _} = q, on_error) do
      run_cmd(cache, :delete_all, [[q]], on_error)
    end

    defp do_evict(false, cache, {:query, q, k}, on_error) do
      _ = run_cmd(cache, :delete_all, [[{:query, q}]], on_error)

      do_evict(false, cache, k, on_error)
    end

    defp do_evict(false, cache, key, on_error) do
      run_cmd(cache, :delete, [key, []], on_error)
    end

    defp do_evict(true, cache, _key, on_error) do
      run_cmd(cache, :delete_all, [], on_error)
    end

    @doc """
    Convenience function for wrapping and/or encapsulating
    the **cache_put** decorator logic.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec eval_cache_put(any(), any(), any(), keyword(), on_error(), match()) :: any()
    def eval_cache_put(cache, key, value, opts, on_error, match) do
      context = Process.get(@decorator_context_key)
      cache = eval_cache(cache, context)
      key = eval_key(key, context)

      do_eval_cache_put(cache, key, value, opts, on_error, match)
    end

    defp do_eval_cache_put(
           cache,
           keyref(cache: ref_cache, key: ref_key, ttl: ttl),
           value,
           opts,
           on_error,
           match
         ) do
      opts = if ttl, do: Keyword.put(opts, :ttl, ttl), else: opts

      eval_cache_put(ref_cache || cache, ref_key, value, opts, on_error, match)
    end

    defp do_eval_cache_put(cache, key, value, opts, on_error, match) do
      case eval_function(match, value) do
        {true, cache_value} ->
          _ = run_cmd(__MODULE__, :cache_put, [cache, key, cache_value, opts], on_error)

          true

        {true, cache_value, new_opts} ->
          _ =
            run_cmd(
              __MODULE__,
              :cache_put,
              [cache, key, cache_value, Keyword.merge(opts, new_opts)],
              on_error
            )

          true

        true ->
          _ = run_cmd(__MODULE__, :cache_put, [cache, key, value, opts], on_error)

          true

        false ->
          false
      end
    end

    @doc """
    Convenience function for the `cache_put` decorator.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec cache_put(cache_value(), {:in, [any()]} | any(), any(), keyword()) :: :ok
    def cache_put(cache, key, value, opts)

    def cache_put(cache, {:in, keys}, value, opts) do
      keys
      |> group_by_cache(cache)
      |> Enum.each(fn
        {cache, [key]} ->
          do_apply(cache, :put, [key, value, opts])

        {cache, keys} ->
          do_apply(cache, :put_all, [Enum.map(keys, &{&1, value}), opts])
      end)
    end

    def cache_put(cache, key, value, opts) do
      do_apply(cache, :put, [key, value, opts])
    end

    @doc """
    Convenience function for evaluating the `cache` argument.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec eval_cache(any(), context()) :: cache_value()
    def eval_cache(cache, ctx)

    def eval_cache(cache, _ctx) when is_atom(cache), do: cache
    def eval_cache(dynamic_cache() = cache, _ctx), do: cache
    def eval_cache(cache, ctx) when is_function(cache, 1), do: cache.(ctx)
    def eval_cache(cache, _ctx) when is_function(cache, 0), do: cache.()
    def eval_cache(cache, _ctx), do: raise_invalid_cache(cache)

    @doc """
    Convenience function for evaluating the `key` argument.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec eval_key(any(), context()) :: any()
    def eval_key(key, ctx)

    # cache_evict: only a query is provided
    def eval_key({:"$nbx_query", q}, ctx) do
      {:query, eval_key(q, ctx)}
    end

    # cache_evict: a query and a key are provided
    def eval_key({:"$nbx_query", q, k}, ctx) do
      {:query, eval_key(q, ctx), eval_key(k, ctx)}
    end

    # The key is a function that expects the context
    def eval_key(key, ctx) when is_function(key, 1) do
      key.(ctx)
    end

    # The key is a function that expects no arguments
    def eval_key(key, _ctx) when is_function(key, 0) do
      key.()
    end

    # The key is a term
    def eval_key(key, _ctx) do
      key
    end

    @doc """
    Convenience function for running a cache command.

    > #### NOTE {: .info}
    >
    > _**This function is for internal purposes only.**_
    """
    @doc group: "Internal API"
    @spec run_cmd(module(), atom(), [any()], on_error()) :: any()
    def run_cmd(cache, fun, args, on_error)

    def run_cmd(cache, fun, args, :nothing) do
      do_apply(cache, fun, args)
    end

    def run_cmd(cache, fun, args, :raise) do
      with {:error, reason} <- do_apply(cache, fun, args) do
        raise reason
      end
    end

    ## Private functions

    defp eval_function(fun, arg) when is_function(fun, 1) do
      fun.(arg)
    end

    defp eval_function(fun, arg) when is_function(fun, 2) do
      fun.(arg, Process.get(@decorator_context_key))
    end

    defp eval_function(other, _arg) do
      other
    end

    defp do_apply(dynamic_cache(cache: cache, name: name), fun, args) do
      apply(cache, fun, [name | args])
    end

    defp do_apply(mod, fun, args) do
      apply(mod, fun, args)
    end

    defp group_by_cache(keys, default_cache) do
      Enum.group_by(
        keys,
        fn
          keyref(cache: cache) when not is_nil(cache) -> cache
          _else -> default_cache
        end,
        fn
          keyref(key: key) -> key
          key -> key
        end
      )
    end

    @compile {:inline, raise_invalid_cache: 1}
    @spec raise_invalid_cache(any()) :: no_return()
    defp raise_invalid_cache(cache) do
      raise ArgumentError,
            "invalid value for :cache option: expected " <>
              "t:Nebulex.Caching.Decorators.cache/0, got: #{inspect(cache)}"
    end
  end
end
