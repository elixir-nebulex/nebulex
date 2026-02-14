defmodule Nebulex.Caching.Decorators.Context do
  @moduledoc """
  Decorator context struct and stack management.

  The context carries metadata about the decorated function being
  executed (decorator name, module, function name, arity, and args).
  It is pushed onto a process-local stack before each decorated call
  and popped afterward, which allows nested decorators to work
  correctly.

  > #### Decorator Advanced Functions {: .warning}
  >
  > Stack helpers (`push/1`, `pop/0`, `get/0`) are low-level APIs intended
  > for advanced integrations. Normal users should not manage decorator
  > context manually.

  ## Struct fields

    * `:decorator` - Decorator's name.
    * `:module` - The invoked module.
    * `:function_name` - The invoked function name.
    * `:arity` - The arity of the invoked function.
    * `:args` - The arguments that are given to the invoked function.

  ## Caveats about the `:args`

  The following are some caveats about the context's `:args`
  to keep in mind:

    * Only arguments explicitly assigned to a variable will be
      included.
    * Ignored or underscored arguments will be ignored.
    * Pattern-matching expressions without a variable assignment
      will be ignored. Therefore, if there is a pattern-matching
      and you want to include its value, it has to be explicitly
      assigned to a variable.

  For example, suppose you have a module with a decorated function:

      defmodule MyApp.SomeModule do
        use Nebulex.Caching, cache: MyApp.Cache

        @decorate cacheable(key: &__MODULE__.key_generator/1)
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

  As you may notice, only the arguments `x` and `z` are included
  in the context args when calling the `key_generator/1` function.
  """

  @typedoc "Decorator type."
  @type decorator() :: :cacheable | :cache_evict | :cache_put

  @typedoc "Decorator context type."
  @type t() :: %__MODULE__{
          decorator: decorator(),
          module: module(),
          function_name: atom(),
          arity: non_neg_integer(),
          args: [any()]
        }

  # Context struct
  defstruct [:decorator, :module, :function_name, arity: 0, args: []]

  ## Context stack management

  # Process dictionary key for the decorator context stack
  @context_key {Nebulex.Caching.Decorators, :decorator_context}

  @doc """
  Pushes the given decorator context onto the stack.

  This is a low-level operation. In custom integrations, pair it with
  `pop/0` in a `try/after` block.

  ## Examples

      iex> alias Nebulex.Caching.Decorators.Context
      iex> ctx = %Context{
      ...>   decorator: :cacheable,
      ...>   module: MyModule,
      ...>   function_name: :get,
      ...>   arity: 1,
      ...>   args: [1]
      ...> }
      iex> Context.push(ctx)
      :ok
      iex> Context.get()
      ctx

  """
  @doc group: "Decorator Advanced Functions"
  @spec push(t()) :: :ok
  def push(%__MODULE__{} = ctx) do
    stack = Process.get(@context_key, [])

    _ignore = Process.put(@context_key, [ctx | stack])

    :ok
  end

  @doc """
  Pops the most recent decorator context from the stack.

  This is a low-level operation intended to be used symmetrically with
  `push/1`.

  Returns the popped context, or `nil` if the stack is empty.

  ## Examples

      iex> alias Nebulex.Caching.Decorators.Context
      iex> outer = %Context{
      ...>   decorator: :cacheable,
      ...>   module: MyModule,
      ...>   function_name: :get,
      ...>   arity: 1,
      ...>   args: [1]
      ...> }
      iex> inner = %Context{
      ...>   decorator: :cache_put,
      ...>   module: MyModule,
      ...>   function_name: :put,
      ...>   arity: 2,
      ...>   args: [1, 2]
      ...> }
      iex> Context.push(outer)
      :ok
      iex> Context.push(inner)
      :ok
      iex> Context.pop()
      inner
      iex> Context.get()
      outer
      iex> Context.pop()
      outer
      iex> Context.pop()
      nil

  Popping the last context deletes the key from the process
  dictionary (no leftover empty list):

      iex> alias Nebulex.Caching.Decorators.Context
      iex> ctx = %Context{
      ...>   decorator: :cacheable,
      ...>   module: MyModule,
      ...>   function_name: :get,
      ...>   arity: 1,
      ...>   args: [1]
      ...> }
      iex> Context.push(ctx)
      :ok
      iex> Context.pop()
      ctx
      iex> Process.get({Nebulex.Caching.Decorators, :decorator_context})
      nil

  """
  @doc group: "Decorator Advanced Functions"
  @spec pop() :: t() | nil
  def pop do
    case Process.get(@context_key, []) do
      [ctx] ->
        _ignore = Process.delete(@context_key)

        ctx

      [ctx | rest] ->
        _ignore = Process.put(@context_key, rest)

        ctx

      [] ->
        nil
    end
  end

  @doc """
  Returns the current decorator context (top of the stack),
  or `nil` if the stack is empty.

  ## Examples

      iex> alias Nebulex.Caching.Decorators.Context
      iex> Context.get()
      nil
      iex> ctx = %Context{
      ...>   decorator: :cache_evict,
      ...>   module: MyModule,
      ...>   function_name: :delete,
      ...>   arity: 1,
      ...>   args: [1]
      ...> }
      iex> Context.push(ctx)
      :ok
      iex> Context.get()
      ctx

  """
  @doc group: "Decorator Advanced Functions"
  @spec get() :: t() | nil
  def get do
    case Process.get(@context_key, []) do
      [ctx | _] -> ctx
      [] -> nil
    end
  end
end
