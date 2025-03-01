defmodule Nebulex.Cache.Observable do
  @moduledoc false

  import Nebulex.Adapter
  import Nebulex.Utils, only: [unwrap_or_raise: 1]

  alias Nebulex.Cache.Options

  @doc """
  Implementation for `c:Nebulex.Cache.register_event_listener/2`.
  """
  def register_event_listener(name, listener, opts) do
    opts = Options.validate_observable_opts!(opts)
    {filter, opts} = Keyword.pop(opts, :filter, &__MODULE__.no_filter/1)
    {metadata, opts} = Keyword.pop!(opts, :metadata)

    do_register_event_listener(name, listener, filter, metadata, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.register_event_listener!/2`.
  """
  def register_event_listener!(name, listener, opts) do
    unwrap_or_raise register_event_listener(name, listener, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.unregister_event_listener/2`.
  """
  defcommand unregister_event_listener(name, id, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.unregister_event_listener!/2`.
  """
  def unregister_event_listener!(name, id, opts) do
    unwrap_or_raise unregister_event_listener(name, id, opts)
  end

  @doc """
  Default filter (no filter).
  """
  def no_filter(_event), do: true

  ## Private functions

  # Inline common instructions
  @compile {:inline, do_register_event_listener: 5}

  # Stream wrapper
  defcommandp do_register_event_listener(name, listener, filter, metadata, opts),
    command: :register_event_listener
end
