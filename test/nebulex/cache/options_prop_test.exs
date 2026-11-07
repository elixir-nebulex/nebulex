defmodule Nebulex.Cache.OptionsPropTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nebulex.Cache.Options

  describe "pop helpers" do
    property "pop_and_validate_timeout! accepts a value if and only if it is a timeout" do
      check all {opts, key} <- opts_and_key() do
        # A timeout is a non-negative integer or `:infinity`.
        value = Keyword.get(opts, key, :infinity)

        if value == :infinity or (is_integer(value) and value >= 0) do
          assert Options.pop_and_validate_timeout!(opts, key) == {value, delete_first(opts, key)}
        else
          assert_raise NimbleOptions.ValidationError, fn ->
            Options.pop_and_validate_timeout!(opts, key)
          end
        end
      end
    end

    property "pop_and_validate_integer! accepts a value if and only if it is an integer" do
      check all {opts, key} <- opts_and_key() do
        value = Keyword.get(opts, key, 0)

        if is_integer(value) do
          assert Options.pop_and_validate_integer!(opts, key) == {value, delete_first(opts, key)}
        else
          assert_raise NimbleOptions.ValidationError, fn ->
            Options.pop_and_validate_integer!(opts, key)
          end
        end
      end
    end
  end

  # Options with integers (negative too), `:infinity` or any term as values.
  # Keys come from a small set, so the chosen key may be missing, present, or
  # repeated.
  defp opts_and_key do
    value = one_of([integer(), constant(:infinity), term()])

    gen all opts <- list_of(tuple({member_of([:a, :b, :c]), value})),
            key <- member_of([:a, :b, :c]) do
      {opts, key}
    end
  end

  # Only the first entry for the key is popped.
  defp delete_first(opts, key) do
    List.keydelete(opts, key, 0)
  end
end
