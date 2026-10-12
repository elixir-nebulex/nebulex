defmodule Nebulex.Utils do
  @moduledoc """
  General purpose utilities.
  """

  # Nebulex wrappable exceptions
  @nbx_wrappable_exception [Nebulex.Error, Nebulex.KeyError]

  # Nebulex exceptions
  @nbx_exception [Nebulex.CacheNotFoundError, Nebulex.QueryError | @nbx_wrappable_exception]

  ## Guards

  @doc """
  Guard that checks whether `e` is a Nebulex exception.

  ## Example

      iex> import Nebulex.Utils, only: [is_nebulex_exception: 1]
      iex> is_nebulex_exception(%Nebulex.Error{reason: :error})
      true
      iex> is_nebulex_exception(%{})
      false

  """
  defguard is_nebulex_exception(e)
           when is_exception(e) and :erlang.map_get(:__struct__, e) in @nbx_exception

  @doc """
  Guard that checks whether `e` is a Nebulex exception that can be wrapped
  in an `{:error, _}` tuple (`Nebulex.Error` or `Nebulex.KeyError`).

  ## Example

      iex> import Nebulex.Utils, only: [is_nebulex_wrappable_exception: 1]
      iex> is_nebulex_wrappable_exception(%Nebulex.Error{reason: :error})
      true
      iex> is_nebulex_wrappable_exception(%Nebulex.KeyError{reason: :error})
      true
      iex> is_nebulex_wrappable_exception(%Nebulex.CacheNotFoundError{})
      false
      iex> is_nebulex_wrappable_exception(%Nebulex.QueryError{})
      false
      iex> is_nebulex_wrappable_exception(%{})
      false

  """
  defguard is_nebulex_wrappable_exception(e)
           when is_exception(e) and :erlang.map_get(:__struct__, e) in @nbx_wrappable_exception

  @doc """
  Guard that checks whether `value` is a timeout: a non-negative integer or
  `:infinity`.

  ## Examples

      iex> import Nebulex.Utils, only: [is_timeout: 1]
      iex> is_timeout(1)
      true
      iex> is_timeout(:infinity)
      true
      iex> is_timeout(-1)
      false
      iex> is_timeout(1.0)
      false
      iex> is_timeout("")
      false
      iex> is_timeout(nil)
      false

  """
  defguard is_timeout(value) when (is_integer(value) and value >= 0) or value == :infinity

  ## Macros

  @doc """
  Unwraps the result of `call`: returns the value from `{:ok, value}`,
  raises the exception from `{:error, exception}`, and returns anything else
  as is.

  ## Example

      iex> import Nebulex.Utils
      iex> unwrap_or_raise {:ok, "ok"}
      "ok"
      iex> unwrap_or_raise {:error, %Nebulex.Error{reason: :error}}
      ** (Nebulex.Error) command failed with reason: :error
      iex> unwrap_or_raise :other
      :other

  """
  defmacro unwrap_or_raise(call) do
    quote do
      case unquote(call) do
        {:ok, result} -> result
        {:error, reason} -> raise reason
        other -> other
      end
    end
  end

  @doc """
  Wraps the result of `call` as `{:ok, result}`.

  ## Example

      iex> import Nebulex.Utils
      iex> wrap_ok "hello"
      {:ok, "hello"}

  """
  defmacro wrap_ok(call) do
    quote do
      {:ok, unquote(call)}
    end
  end

  @doc """
  Builds `exception` with `opts` and wraps it as `{:error, exception}`.

  ## Example

      iex> import Nebulex.Utils
      iex> wrap_error Nebulex.Error, reason: :error
      {:error, %Nebulex.Error{reason: :error}}

  """
  defmacro wrap_error(exception, opts) do
    quote do
      {:error, unquote(exception).exception(unquote(opts))}
    end
  end

  ## Utility functions

  @doc """
  Like `Keyword.get/3`, but validates the value with `valid?`.

  Raises `ArgumentError` when the validation fails. When the key is missing,
  returns `default`, calling it first if it is a zero-arity function.

  ## Examples

      iex> Nebulex.Utils.get_option(
      ...>   [keys: [1, 2, 3]],
      ...>   :keys,
      ...>   "a list with at least one element",
      ...>   &(match?([_ | _], &1) or is_nil(&1))
      ...> )
      [1, 2, 3]

      iex> Nebulex.Utils.get_option(
      ...>   [],
      ...>   :keys,
      ...>   "a list with at least one element",
      ...>   &(match?([_ | _], &1) or is_nil(&1))
      ...> )
      nil

      iex> Nebulex.Utils.get_option(
      ...>   [],
      ...>   :keys,
      ...>   "a list with at least one element",
      ...>   &(match?([_ | _], &1) or is_nil(&1)),
      ...>   fn -> "default" end
      ...> )
      "default"

      iex> Nebulex.Utils.get_option(
      ...>   [keys: 123],
      ...>   :keys,
      ...>   "non empty list",
      ...>   &(match?([_ | _], &1) or is_nil(&1))
      ...> )
      ** (ArgumentError) invalid value for :keys option: expected non empty list, got: 123

  """
  @spec get_option(keyword(), atom(), binary(), (any() -> boolean()), fun() | any()) :: any()
  def get_option(opts, key, expected, valid?, default \\ nil)
      when is_list(opts) and is_atom(key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        if valid?.(value) do
          value
        else
          raise ArgumentError,
                "invalid value for #{inspect(key)} option: expected #{expected}, got: #{inspect(value)}"
        end

      :error ->
        if is_function(default, 0) do
          default.()
        else
          default
        end
    end
  end

  @doc """
  Returns the implemented behaviours for the given `module`.
  """
  @spec module_behaviours(module()) :: [module()]
  def module_behaviours(module) do
    for {:behaviour, behaviours} <- module.__info__(:attributes), behaviour <- behaviours do
      behaviour
    end
  end

  @doc """
  Camelizes each element of `list` and concatenates them into an alias.

  It handles binaries, atoms, and numbers.

  ## Examples

      iex> Nebulex.Utils.camelize_and_concat([Foo, :bar])
      Foo.Bar

      iex> Nebulex.Utils.camelize_and_concat([Foo, "bar"])
      Foo.Bar

      iex> Nebulex.Utils.camelize_and_concat([Foo, "Bar", 1])
      :"Elixir.Foo.Bar.1"

  """
  @spec camelize_and_concat([atom() | binary() | number()]) :: atom()
  def camelize_and_concat(list) when is_list(list) do
    list
    |> Enum.map(&Macro.camelize("#{&1}"))
    |> Module.concat()
  end
end
