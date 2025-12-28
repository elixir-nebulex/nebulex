<!--
The following rules are sourced from [UsageRules](https://github.com/ash-project/usage_rules),
with modifications and additions.

SPDX-FileCopyrightText: 2025 usage_rules contributors <https://github.com/ash-project/usage_rules/graphs.contributors>

SPDX-License-Identifier: MIT
-->
# Elixir Core Usage Rules

## Pattern Matching

- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling

- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`
- Bang functions (`!`) that explicitly raise exceptions on failure are acceptable (e.g., `File.read!/1`, `String.to_integer!/1`)
- Avoid rescuing exceptions unless for a very specific case (e.g., cleaning up resources, logging critical errors)

## Common Mistakes to Avoid

- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design

- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures

- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!--
The following rules are sourced from [Phoenix Framework](https://github.com/phoenixframework/phoenix),
with modifications and additions.

Copyright (c) 2014 Chris McCord, licensed under the MIT License.
-->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

- The `in` operator in guards requires a compile-time known value on the right side (literal list or range)

  **Never do this (invalid)**: using a variable which is unknown at compile time

      def t(x, y) when x in y, do: {x, y}

  This will raise `ArgumentError: invalid right argument for operator "in", it expects a compile-time proper list or compile-time range on the right side when used in guard expressions`

  **Valid**: use a known value for the list or range

      def t(x, y) when x in [1, 2, 3], do: {x, y}
      def t(x, y) when x in 1..10, do: {x, y}

- In tests, avoid using `assert` with pattern matching when the expected value is fully known. Use direct equality comparison instead for clearer test failures

  **Avoid**:

      assert {:ok, ^value} = testing()
      assert {:error, :not_found} = fetch()

  **Prefer**:

      assert testing() == {:ok, value}
      assert fetch() == {:error, :not_found}

  **Exception**: Pattern matching is acceptable when you only want to assert part of a complex structure

      # OK: asserting only specific fields of a large struct/map
      assert {:ok, %{id: ^id}} = get_order()

- In tests, avoid duplicating test data across multiple tests. Use constants, fixture files, or private fixture functions instead

  **Avoid**: Duplicating test data

      test "validates user email" do
        assert valid_email?("user@example.com")
      end

      test "creates user" do
        assert create_user("user@example.com")
      end

  **Prefer**: Use module attributes for constants or fixture functions

      @valid_email "user@example.com"

      test "validates user email" do
        assert valid_email?(@valid_email)
      end

      test "creates user" do
        assert create_user(@valid_email)
      end

  For complex data structures, create fixture functions:

      defp user_fixture(attrs \\ %{}) do
        %User{
          name: "John Doe",
          email: "john@example.com",
          age: 30
        }
        |> Map.merge(attrs)
      end

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Elixir Style

- Primarily, follow the [The Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide/blob/master/README.md).

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

  **Prefer**:

      def some_function(some_data) do
        some_data |> other_function() |> List.first()
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
