defmodule Nebulex.Caching.Decorators.Runtime do
  @moduledoc false

  import Record

  alias Nebulex.Caching.Decorators.Context

  ## Records

  # Dynamic cache spec
  defrecordp(:dynamic_cache, :"$nbx_dynamic_cache_spec", cache: nil, name: nil)

  # Key reference spec
  defrecordp(:keyref, :"$nbx_keyref_spec", cache: nil, key: nil, ttl: nil)

  ## Internal API

  @doc false
  @spec eval_cacheable(any(), any(), any(), keyword(), any(), atom(), fun()) :: any()
  def eval_cacheable(cache, key, references, opts, match, on_error, block_fun) do
    context = Context.get()
    cache = eval_cache(cache, context)
    key = eval_key(key, context)

    do_eval_cacheable(cache, key, references, opts, match, on_error, block_fun)
  end

  @doc false
  @spec eval_cache_evict(any(), any(), boolean(), boolean(), atom(), fun()) :: any()
  def eval_cache_evict(cache, key, before?, all_entries?, on_error, block_fun) do
    context = Context.get()
    cache = eval_cache(cache, context)
    key = eval_key(key, context)

    do_eval_cache_evict(cache, key, before?, all_entries?, on_error, block_fun)
  end

  @doc false
  @spec eval_cache_put(any(), any(), any(), keyword(), atom(), any()) :: any()
  def eval_cache_put(cache, key, value, opts, on_error, match) do
    context = Context.get()
    cache = eval_cache(cache, context)
    key = eval_key(key, context)

    do_eval_cache_put(cache, key, value, opts, on_error, match)
  end

  @doc false
  @spec cache_put(any(), {:in, [any()]} | any(), any(), keyword()) :: :ok
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

  @doc false
  @spec eval_cache(any(), Context.t()) :: any()
  def eval_cache(cache, ctx)

  def eval_cache(cache, _ctx) when is_atom(cache), do: cache
  def eval_cache(dynamic_cache() = cache, _ctx), do: cache
  def eval_cache(cache, ctx) when is_function(cache, 1), do: cache.(ctx)
  def eval_cache(cache, _ctx) when is_function(cache, 0), do: cache.()
  def eval_cache(cache, _ctx), do: raise_invalid_cache(cache)

  @doc false
  @spec eval_key(any(), Context.t()) :: any()
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

  @doc false
  @spec run_cmd(module(), atom(), [any()], atom()) :: any()
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

  defp do_eval_cacheable(cache, key, nil, opts, match, on_error, block_fun) do
    do_apply(cache, :fetch, [key, opts])
    |> handle_cacheable(
      on_error,
      block_fun,
      &eval_cache_put(cache, key, &1, opts, on_error, match)
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
          _ignore = do_apply(cache, :delete, [key])

          false
        end
      end,
      fn value ->
        case eval_function(match, value) do
          false ->
            # Remove the parent's key reference
            _ignore = do_apply(cache, :delete, [key])

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
        handle_cacheable(
          other,
          on_error,
          block_fun,
          &handle_cacheable_ref(&1, cache, key, references, opts, match, on_error)
        )
    end
  end

  defp handle_cacheable_ref(result, cache, key, references, opts, match, on_error) do
    with {:ok, reference} <- eval_cacheable_ref(references, result),
         true <- eval_cache_put(cache, reference, result, opts, on_error, match) do
      :ok = cache_put(cache, key, reference, opts)
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

  defp do_eval_cache_evict(cache, key, true, all_entries?, on_error, block_fun) do
    _ignore = do_evict(all_entries?, cache, key, on_error)

    block_fun.()
  end

  defp do_eval_cache_evict(cache, key, false, all_entries?, on_error, block_fun) do
    result = block_fun.()

    _ignore = do_evict(all_entries?, cache, key, on_error)

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
    _ignore = run_cmd(cache, :delete_all, [[{:query, q}]], on_error)

    do_evict(false, cache, k, on_error)
  end

  defp do_evict(false, cache, key, on_error) do
    run_cmd(cache, :delete, [key, []], on_error)
  end

  defp do_evict(true, cache, _key, on_error) do
    run_cmd(cache, :delete_all, [], on_error)
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
        _ignore = run_cmd(__MODULE__, :cache_put, [cache, key, cache_value, opts], on_error)

        true

      {true, cache_value, new_opts} ->
        _ignore =
          run_cmd(
            __MODULE__,
            :cache_put,
            [cache, key, cache_value, Keyword.merge(opts, new_opts)],
            on_error
          )

        true

      true ->
        _ignore = run_cmd(__MODULE__, :cache_put, [cache, key, value, opts], on_error)

        true

      false ->
        false
    end
  end

  defp do_apply(dynamic_cache(cache: cache, name: name), fun, args) do
    default_dynamic_cache = cache.get_dynamic_cache()

    try do
      _ignore = cache.put_dynamic_cache(name)

      apply(cache, fun, args)
    after
      _ignore = cache.put_dynamic_cache(default_dynamic_cache)
    end
  end

  defp do_apply(mod, fun, args) do
    apply(mod, fun, args)
  end

  defp eval_function(fun, arg) when is_function(fun, 1) do
    fun.(arg)
  end

  defp eval_function(fun, arg) when is_function(fun, 2) do
    fun.(arg, Context.get())
  end

  defp eval_function(other, _arg) do
    other
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

  @compile inline: [raise_invalid_cache: 1]
  @spec raise_invalid_cache(any()) :: no_return()
  defp raise_invalid_cache(cache) do
    raise ArgumentError,
          "invalid value for :cache option: expected " <>
            "t:Nebulex.Caching.Decorators.cache/0, got: #{inspect(cache)}"
  end
end
