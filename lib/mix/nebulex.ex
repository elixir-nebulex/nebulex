defmodule Mix.Nebulex do
  # Conveniences for writing Mix.Tasks in Nebulex.
  @moduledoc false

  alias Mix.Project

  @doc """
  Raises if `task` is run from the root of an umbrella project.
  """
  def no_umbrella!(task) do
    if Project.umbrella?() do
      Mix.raise(
        "Cannot run task #{inspect(task)} from umbrella project root. " <>
          "Change directory to one of the umbrella applications and try again"
      )
    end
  end
end
