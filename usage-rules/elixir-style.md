# Elixir Style

> Most of these guidelines are based on
> [The Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
> by Christopher Adams, licensed under
> [CC-BY-3.0](https://creativecommons.org/licenses/by/3.0/).

## Formatting

### Whitespace

- Use blank lines between `def`s to break up a function into logical paragraphs.
  For example:

  ```elixir
  def some_function(some_data) do
    some_data |> other_function() |> List.first()
  end

  def some_function do
    result
  end

  def some_other_function do
    another_result
  end

  def a_longer_function do
    one
    two

    three
    four
  end
  ```

- If the function head and `do:` clause are too long to fit on the same line, put `do:` on a new line, indented one level more than the previous line. For example:

  ```elixir
  def some_function([:foo, :bar, :baz] = args),
    do: Enum.map(args, fn arg -> arg <> " is on a very long line!" end)
  ```

  When the `do:` clause starts on its own line, treat it as a multiline function by separating it with blank lines.

  ```elixir
  # not preferred
  def some_function([]), do: :empty
  def some_function(_),
    do: :very_long_line_here

  # preferred
  def some_function([]), do: :empty

  def some_function(_),
    do: :very_long_line_here
  ```

- Add a blank line after a multiline assignment as a visual cue that the assignment is 'over'. For example:

  ```elixir
  # not preferred
  some_string =
    "Hello"
    |> String.downcase()
    |> String.trim()
  another_string <> some_string

  # preferred
  some_string =
    "Hello"
    |> String.downcase()
    |> String.trim()

  another_string <> some_string
  ```

  ```elixir
  # also not preferred
  something =
    if x == 2 do
      "Hi"
    else
      "Bye"
    end
  String.downcase(something)

  # preferred
  something =
    if x == 2 do
      "Hi"
    else
      "Bye"
    end

  String.downcase(something)
  ```

### Parentheses

- Use parentheses when defining a type.

  ```elixir
  # not preferred
  @type name :: atom

  # preferred
  @type name() :: atom
  ```

## Gneral guidelines

The rules in this section may not be applied by the code formatter, but they are generally preferred practice.

### Expressions

- Run single-line `def`s that match for the same function together, but separate multiline `def`s with a blank line. For example:

  ```elixir
  def some_function(nil), do: {:error, "No Value"}
  def some_function([]), do: :ok

  def some_function([first | rest]) do
    some_function(rest)
  end
  ```

- If you have more than one multiline `def`, do not use single-line `def`s. For example:

  ```elixir
  def some_function(nil) do
    {:error, "No Value"}
  end

  def some_function([]) do
    :ok
  end

  def some_function([first | rest]) do
    some_function(rest)
  end

  def some_function([first | rest], opts) do
    some_function(rest, opts)
  end
  ```

- Use the pipe operator to chain functions together. For example:

  ```elixir
  # not preferred
  String.trim(String.downcase(some_string))

  # preferred
  some_string |> String.downcase() |> String.trim()

  # Multiline pipelines are not further indented
  some_string
  |> String.downcase()
  |> String.trim()

  # Multiline pipelines on the right side of a pattern match
  # should be indented on a new line
  sanitized_string =
    some_string
    |> String.downcase()
    |> String.trim()
  ```

- Avoid using the pipe operator just once, unless the first expression is a function. For example:

  ```elixir
  # not preferred
  some_string |> String.downcase()

  # preferred
  String.downcase(some_string)

  # not preferred
  Version.parse(System.version())

  # preferred
  System.version() |> Version.parse()
  ```

- Use parentheses when a `def` has arguments, and omit them when it doesn't. For example:

  ```elixir
  # not preferred
  def some_function arg1, arg2 do
    # body omitted
  end

  def some_function() do
    # body omitted
  end

  # preferred
  def some_function(arg1, arg2) do
    # body omitted
  end

  def some_function do
    # body omitted
  end
  ```

- Use `do:` for single line `if/unless` statements.

  ```elixir
  # preferred
  if some_condition, do: # some_stuff
  ```

- Use `true` as the last condition of the `cond` special form when you need a clause that always matches.

  ```elixir
  # not preferred
  cond do
    1 + 2 == 5 ->
      "Nope"

    1 + 3 == 5 ->
      "Uh, uh"

    :else ->
      "OK"
  end

  # preferred
  cond do
    1 + 2 == 5 ->
      "Nope"

    1 + 3 == 5 ->
      "Uh, uh"

    true ->
      "OK"
  end
  ```

### Naming

- Use `snake_case` for atoms, functions and variables.

  ```elixir
  # not preferred
  :"some atom"
  :SomeAtom
  :someAtom

  someVar = 5

  def someFunction do
    ...
  end

  # preferred
  :some_atom

  some_var = 5

  def some_function do
    ...
  end
  ```

- Use `CamelCase` for modules (keep acronyms like HTTP, RFC, XML uppercase).

  ```elixir
  # not preferred
  defmodule Somemodule do
    ...
  end

  defmodule Some_Module do
    ...
  end

  defmodule SomeXml do
    ...
  end

  # preferred
  defmodule SomeModule do
    ...
  end

  defmodule SomeXML do
    ...
  end
  ```

- Functions that return a boolean (`true` or `false`) should be named with a trailing question mark.

  ```elixir
  def cool?(var) do
    String.contains?(var, "cool")
  end
  ```

- Boolean checks that can be used in guard clauses (custom guards) should be named with an `is_` prefix.

  ```elixir
  defguard is_cool(var) when var == "cool"
  defguard is_very_cool(var) when var == "very cool"
  ```

### Comments

- Write expressive code and try to convey your program's intention through control-flow, structure and naming.

- Comments longer than a word are capitalized, and sentences use punctuation. Use one space after periods.

```elixir
# not preferred
# these lowercase comments are missing punctuation

# preferred
# Capitalization example
# Use punctuation for complete sentences.
```

- Limit comment lines to 80 characters.

#### Comment Annotations

- Annotations should usually be written on the line immediately above the relevant code.

- The annotation keyword is uppercase, and is followed by a colon and a space, then a note describing the problem.

```elixir
# TODO: Deprecate in v1.5.
def some_function(arg), do: {:ok, arg}
```

- In cases where the problem is so obvious that any documentation would be redundant, annotations may be left with no note. This usage should be the exception and not the rule.

```elixir
start_task()

# FIXME
Process.sleep(5000)
```

- Use `TODO` to note missing features or functionality that should be added at a later date.

- Use `FIXME` to note broken code that needs to be fixed.

- Use `OPTIMIZE` to note slow or inefficient code that may cause performance problems.

- Use `HACK` to note code smells where questionable coding practices were used and should be refactored away.

- Use `REVIEW` to note anything that should be looked at to confirm it is working as intended. For example: `REVIEW: Are we sure this is how the client does X currently?`

- Use other custom annotation keywords if it feels appropriate, but be sure to document them in your project's `README` or similar.

### Comment Constants

- When defining a constant, pick a descriptive name that reflects the intention or usage of the constant and add a comment with a short description.

**Not preferred:**

```elixir
@retries 10
```

**Preferred:**

```elixir
# Default HTTP retries
@http_retries 10
```

- When the constant is a timeout in milliseconds, use `:timer` module instead of explicit value (e.g., `:timer.seconds/1`, `:timer.minutes/1`, `:timer.hours/1`).

**Not preferred:**

```elixir
# Default HTTP request timeout in milliseconds
@http_rrequest_timeout 10_000
```

**Preferred:**

```elixir
# Default HTTP request timeout in milliseconds
@http_rrequest_timeout :timer.seconds(10)
```

- When the constant is a list of atoms or strings, a regex, or anything that can be expressed using a "Sigils", then use "Sigils".

**Not preferred:**

```elixir
# User types
@user_types [:admin, :editor, :customer]

# Supported country codes
@user_types ["US", "ES", "CO"]
```

**Preferred:**

```elixir
# User types
@user_types ~w(admin editor customer)a

# Supported country codes
@user_types ~w(US ES CO)
```

### Modules

- List module attributes, directives, and macros in the following order:

  1. `@moduledoc`
  2. `@behaviour`
  3. `use`
  4. `import`
  5. `require`
  6. `alias`
  7. `@module_attribute`
  8. `defstruct`
  9. `@type`
  10. `@callback`
  11. `@macrocallback`
  12. `@optional_callbacks`
  13. `defmacro`, `defmodule`, `defguard`, `def`, etc.

  Add a blank line between each grouping, and sort the terms (like module names) alphabetically. Here's an overall example of how you should order things in your modules:

  ```elixir
  defmodule MyModule do
    @moduledoc """
    An example module
    """

    @behaviour MyBehaviour

    use GenServer

    import Something
    import SomethingElse

    require Integer

    alias My.Long.Module.Name
    alias My.Other.Module.Example

    @module_attribute :foo
    @other_attribute 100

    defstruct [:name, params: []]

    @type params :: [{binary, binary}]

    @callback some_function(term) :: :ok | {:error, term}

    @macrocallback macro_name(term) :: Macro.t()

    @optional_callbacks macro_name: 1

    @doc false
    defmacro __using__(_opts), do: :no_op

    @doc """
    Determines when a term is `:ok`. Allowed in guards.
    """
    defguard is_ok(term) when term == :ok

    @impl true
    def init(state), do: {:ok, state}

    # Define other functions here.
  end
  ```

- Use the `__MODULE__` pseudo variable when a module refers to itself. This avoids having to update any self-references when the module name changes.

  ```elixir
  defmodule SomeProject.SomeModule do
    defstruct [:name]

    def name(%__MODULE__{name: name}), do: name
  end

### Typespecs

- Place `@typedoc` and `@type` definitions together, and separate each pair with a blank line.

  ```elixir
  defmodule SomeModule do
    @moduledoc false

    @typedoc "The name"
    @type name() :: atom()

    @typedoc "The result"
    @type result() :: {:ok, any()} | {:error, any()}

    ...
  end
  ```

- Name the main type for a module `t()`, for example: the type specification for a struct.

  ```elixir
  defstruct name: nil, params: []

  @typedoc "The type for ..."
  @type t() :: %__MODULE__{
          name: String.t() | nil,
          params: Keyword.t()
        }
  ```

- Place specifications right before the function definition, after the `@doc`, without separating them by a blank line.

  ```elixir
  @doc """
  Some function description.
  """
  @spec some_function(any()) :: result()
  def some_function(some_data) do
    {:ok, some_data}
  end

### Structs

- Use a list of atoms for struct fields that default to `nil`, followed by the other keywords.

  ```elixir
  # not preferred
  defstruct name: nil, params: nil, active: true

  # preferred
  defstruct [:name, :params, active: true]
  ```

- Omit square brackets when the argument of a `defstruct` is a keyword list.

  ```elixir
  # not preferred
  defstruct [params: [], active: true]

  # preferred
  defstruct params: [], active: true

  # required - brackets are not optional, with at least one atom in the list
  defstruct [:name, params: [], active: true]
  ```

- If a struct definition spans multiple lines, put each element on its own line, keeping the elements aligned.

  ```elixir
  defstruct foo: "test",
            bar: true,
            baz: false,
            qux: false,
            quux: 1
  ```

  If a multiline struct requires brackets, format it as a multiline list:

  ```elixir
  defstruct [
    :name,
    params: [],
    active: true
  ]
  ```

### Exceptions

- Make exception names end with a trailing `Error`.

  ```elixir
  # not preferred
  defmodule BadHTTPCode do
    defexception [:message]
  end

  defmodule BadHTTPCodeException do
    defexception [:message]
  end

  # preferred
  defmodule BadHTTPCodeError do
    defexception [:message]
  end
  ```

- Use lowercase error messages when raising exceptions, with no trailing punctuation.

  ```elixir
  # not preferred
  raise ArgumentError, "This is not valid."

  # preferred
  raise ArgumentError, "this is not valid"
  ```

### Collections

- Always use the special syntax for keyword lists.

  ```elixir
  # not preferred
  some_value = [{:a, "baz"}, {:b, "qux"}]

  # preferred
  some_value = [a: "baz", b: "qux"]
  ```

- Use the shorthand key-value syntax for maps when all of the keys are atoms.

  ```elixir
  # not preferred
  %{:a => 1, :b => 2, :c => 0}

  # preferred
  %{a: 1, b: 2, c: 3}
  ```

- Use the verbose key-value syntax for maps if any key is not an atom.

  ```elixir
  # not preferred
  %{"c" => 0, a: 1, b: 2}

  # preferred
  %{:a => 1, :b => 2, "c" => 0}
  ```

### Testing

- When writing ExUnit assertions, put the expression being tested to the left of the operator, and the expected result to the right, unless the assertion is a pattern match.

  ```elixir
  # not preferred
  assert true == actual_function(1)

  # preferred
  assert actual_function(1) == true

  # required - the assertion is a pattern match, and the `expected` variable is used later
  assert {:ok, expected} = actual_function(3)
  assert expected.atom == :atom
  assert expected.int == 123

  # preferred - if the right side is known, even it it is a tuple
  assert actual_function(11) == {:ok, %{atom: :atom, int: 123}}

  # preferred - if the right side is known (using a variable)
  expected = %{atom: :atom, int: 123}
  assert actual_function(11) == {:ok, expected}
  ```

## Extra guidelines

- Use a blank line for the return or final statement (unless it is a single line).

  **Avoid**:

      def some_function(arg) do
        Logger.info("Arg: #{inspect(some_data)}")
        :ok
      end

  **Prefer**:

      def some_function(some_data) do
        Logger.info("Arg: #{inspect(some_data)}")

        :ok
      end

- Use multi-line when a function returns with a pipe.

  **Avoid**:

      def some_function(some_data) do
        some_data |> other_function() |> List.first()
      end

  **Prefer**:

      def some_function(some_data) do
        some_data
        |> other_function()
        |> List.first()
      end

- Use `with` when only one case has to be handled, either the success or the error.

  **Avoid**: `case` forwarding the same result

      case some_call() do
        :ok ->
          :ok

        {:error, reason} = error ->
          Logger.error("Error: #{inspect(reason)}")

          error
      end

  **Prefer**: `with` handling only the needed case

      with {:error, reason} = error <- some_call() do
        Logger.error("Error: #{inspect(reason)}")

        error
      end
