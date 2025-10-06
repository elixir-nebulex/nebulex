defmodule Nebulex.Caching.Options do
  @moduledoc false

  # Options given to the __using__ macro
  use_caching_opts = [
    default_key_generator: [
      type: {:custom, __MODULE__, :__validate_keygen__, []},
      type_doc: "`t:Nebulex.Caching.Decorators.key/0`",
      required: false,
      doc: """
      Defines the default key generation function for all decorated functions
      in the module. This can be overridden at the decorator level using the
      `:key` option.

      The function must be provided in the format `&Mod.fun/arity`.

      The default value is `&Nebulex.Caching.Decorators.generate_key/1`.
      """
    ],
    cache: [
      type: :atom,
      required: false,
      doc: """
      Defines the default cache for all decorated functions in the module.
      This can be overridden at the decorator level.
      """
    ],
    on_error: [
      type: {:in, [:nothing, :raise]},
      type_doc: "`t:Nebulex.Caching.Decorators.on_error/0`",
      required: false,
      default: :nothing,
      doc: """
      Defines the default error handling behavior for all decorated functions
      in the module when a cache error occurs. This can be overridden at the
      decorator level.

      Possible values:

        * `:nothing` - Ignores cache errors (default).
        * `:raise` - Raises an exception when a cache error occurs.

      """
    ],
    match: [
      type: {:custom, __MODULE__, :__validate_match__, []},
      type_doc: "`t:Nebulex.Caching.Decorators.match/0`",
      required: false,
      doc: """
      Defines the default match function for all decorated functions in the
      module. This can be overridden at the decorator level.

      The function must be provided in the format `&Mod.fun/arity`.

      The default value is `&Nebulex.Caching.Decorators.default_match/1`.
      """
    ],
    opts: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: """
      The default options to use globally for all decorated functions in the
      module when invoking cache commands.
      """
    ]
  ]

  # Shared decorator options
  shared_opts = [
    cache: [
      type: :any,
      type_doc: "`t:cache/0`",
      required: true,
      doc: """
      The cache to use. When present, this option overrides the
      [default or global cache](#module-default-cache).
      See `t:cache/0` for possible values.

      Raises an exception if the `:cache` option is not provided in the
      decorator declaration and is not configured when defining the
      caching usage via `use Nebulex.Caching` either.

      See the ["Cache configuration"](#module-cache-configuration) section
      for more information.
      """
    ],
    key: [
      type: :any,
      type_doc: "`t:key/0`",
      required: false,
      doc: """
      The cache access key the decorator will use when running the decorated
      function. When this option is not provided, the default key generator
      generates a key based on the function arguments.

      The `:key` option accepts the following values:

        * **An anonymous function** - A function that generates the key at
          runtime. The function can optionally receive the decorator context
          as an argument and must return the key for caching.

        * **The tuple `{:in, keys}`** - Where `keys` is a list of keys to
          evict or update. Under the hood, `cache.delete_all(in: keys)` or
          `cache.put_all(entries)` is invoked. This option is only allowed
          for the `cache_evict` and `cache_put` decorators.

        * **Any term** - A literal value to use as the cache key.

      See the ["Key Generation"](#module-key-generation) section
      for more information.
      """
    ],
    match: [
      type: {:or, [fun: 1, fun: 2]},
      type_doc: "`t:match/0`",
      required: false,
      doc: """
      An anonymous function that decides whether the result of evaluating the
      decorated function should be cached. The function receives the result
      as its first argument and can optionally receive the decorator context
      as a second argument.

      The match function can return:

        * `true` - The value returned by the decorated function is cached
          (this is the default behavior).

        * `{true, value}` - The specified `value` is cached instead of the
          original return value. This is useful when you need to customize
          what gets cached.

        * `{true, value, opts}` - The specified `value` is cached with the
          provided options `opts`. This allows you to customize both what
          gets cached and the caching options at runtime
          (e.g., `{true, value, [ttl: @ttl]}`).

        * `false` - Nothing is cached.

      The default match function is defined as:

      ```elixir
      def default_match({:error, _}), do: false
      def default_match(:error), do: false
      def default_match(nil), do: false
      def default_match(_other), do: true
      ```

      By default, if the decorated function returns `{:error, term}`, `:error`,
      or `nil`, the value is not cached. Otherwise, the value is cached.

      When configured, this option overrides the global value (if any) defined
      via `use Nebulex.Caching, match: &MyApp.match/1`.

      The default value is `&Nebulex.Caching.Decorators.default_match/1`.
      """
    ],
    on_error: [
      type: {:in, [:nothing, :raise]},
      type_doc: "`t:on_error/0`",
      required: false,
      default: :nothing,
      doc: """
      Defines the error handling behavior when a cache error occurs during
      decorator execution.

      Possible values:

        * `:nothing` - Ignores the error and continues execution (default).
        * `:raise` - Raises an exception when a cache error occurs.

      When configured, this option overrides the global value (if any) defined
      via `use Nebulex.Caching, on_error: ...`.
      """
    ],
    opts: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: """
      The options used by the decorator when invoking cache commands. These
      options are passed directly to the underlying cache operations.
      """
    ]
  ]

  # cacheable options
  cacheable_opts = [
    references: [
      type: {:or, [{:fun, 1}, {:fun, 2}, :any]},
      type_doc: "`t:references/0`",
      required: false,
      doc: """
      Indicates that the key specified by the `:key` option references another
      key provided by this option. When present, the `cacheable` decorator
      stores the decorated function's result under both the referenced key
      (provided by `:references`) and the primary key (provided by `:key`).

      See `t:references/0` for possible values.

      For more information and examples, see the
      ["Referenced keys"](#cacheable/3-referenced-keys) section.
      """
    ]
  ]

  # cache_evict options
  cache_evict_opts = [
    all_entries: [
      type: :boolean,
      required: false,
      default: false,
      doc: """
      When set to `true`, the decorator removes all entries from the cache,
      ignoring the `:key` and `:query` options.

      Default: `false`
      """
    ],
    before_invocation: [
      type: :boolean,
      required: false,
      default: false,
      doc: """
      When set to `true`, the cache eviction occurs before the decorated
      function is invoked. When `false`, the eviction occurs after the
      function completes successfully.

      Default: `false`
      """
    ],
    query: [
      type: :any,
      type_doc: "`t:query/0`",
      required: false,
      doc: """
      The query to use for evicting cache entries. When present, this option
      overrides the `:key` option and allows you to evict multiple entries
      based on specific criteria.

      The `:query` option accepts the following values:

        * **An anonymous function** - A function that generates the query at
          runtime. The function can optionally receive the decorator context
          as an argument and must return a query supported by the cache
          adapter. This is useful when the query depends on function arguments
          or needs to be built dynamically.

        * **A direct query value** - Any term that is a valid query supported
          by the cache adapter. This is suitable for static queries that don't
          depend on runtime values.

      See the ["Eviction with a query"](#cache_evict/3-eviction-with-a-query)
      section for more details and examples.
      """
    ]
  ]

  # `use` options schema
  @use_opts_schema NimbleOptions.new!(use_caching_opts)

  # shared options schema
  @shared_opts_schema NimbleOptions.new!(shared_opts)

  # `cacheable` options schema
  @cacheable_opts_schema NimbleOptions.new!(cacheable_opts)

  # `cache_evict` options schema
  @cache_evict_opts_schema NimbleOptions.new!(cache_evict_opts)

  ## Docs API

  # coveralls-ignore-start

  @spec use_options_docs() :: binary()
  def use_options_docs do
    NimbleOptions.docs(@use_opts_schema)
  end

  @spec shared_options_docs() :: binary()
  def shared_options_docs do
    NimbleOptions.docs(@shared_opts_schema)
  end

  @spec cacheable_options_docs() :: binary()
  def cacheable_options_docs do
    NimbleOptions.docs(@cacheable_opts_schema)
  end

  @spec cache_evict_options_docs() :: binary()
  def cache_evict_options_docs do
    NimbleOptions.docs(@cache_evict_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate_use_opts!(keyword()) :: keyword()
  def validate_use_opts!(opts) do
    NimbleOptions.validate!(opts, @use_opts_schema)
  end

  ## Helpers

  # sobelow_skip ["RCE.CodeModule"]
  @doc false
  def __validate_keygen__(keygen) do
    {value, _binding} = Code.eval_quoted(keygen)

    if is_function(value, 1) do
      {:ok, value}
    else
      {:error, "expected function of arity 1, got: #{inspect(value)}"}
    end
  end

  # sobelow_skip ["RCE.CodeModule"]
  @doc false
  def __validate_match__(match) do
    {value, _binding} = Code.eval_quoted(match)

    if is_function(value, 1) or is_function(value, 2) do
      {:ok, value}
    else
      {:error, "expected function of arity 1 or 2, got: #{inspect(value)}"}
    end
  end
end
