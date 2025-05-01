defmodule Mix.Tasks.Nbx.Gen.Cache do
  @shortdoc "Generates a new cache"

  @moduledoc """
  Generates a new cache.

  The cache will be placed in the `lib` directory.

  ## Examples

      $ mix nbx.gen.cache -c MyApp.Cache

  ## Command line options

    * `-c`, `--cache` - The cache to generate.

  """

  use Mix.Task

  import Mix.Generator
  import Mix.Nebulex

  alias Mix.Project

  @switches [
    cache: [:string, :keep]
  ]

  @aliases [
    c: :cache
  ]

  @impl true
  def run(args) do
    no_umbrella!("nbx.gen.cache")
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    cache = get_cache(opts)
    config = Project.config()
    underscored = Macro.underscore(inspect(cache))

    base = Path.basename(underscored)
    file = Path.join("lib", underscored) <> ".ex"
    app = config[:app] || :YOUR_APP_NAME
    opts = [mod: cache, app: app, base: base]

    create_directory(Path.dirname(file))
    create_file(file, cache_template(opts))
    config_path = config[:config_path] || "config/config.exs"

    case File.read(config_path) do
      {:ok, contents} ->
        check = String.contains?(contents, "import Config")
        config_first_line = get_first_config_line(check) <> "\n"
        new_contents = config_first_line <> "\n" <> config_template(opts)

        Mix.shell().info([:green, "* updating ", :reset, config_path])
        File.write!(config_path, String.replace(contents, config_first_line, new_contents))

      {:error, _} ->
        create_file(config_path, "import Config\n\n" <> config_template(opts))
    end

    Mix.shell().info("""
    Don't forget to add your new cache to your supervision tree
    (typically in lib/#{app}/application.ex):

        def start(_type, _args) do
          children = [
            #{inspect(cache)},
          ]

    For more information about configuration options, check
    adapters documentation and Nebulex.Cache shared options.
    """)
  end

  defp get_cache(opts) do
    case Keyword.get_values(opts, :cache) do
      [] -> Mix.raise("nbx.gen.cache expects the cache to be given as -c MyApp.Cache")
      [cache] -> Module.concat([cache])
      [_ | _] -> Mix.raise("nbx.gen.cache expects a single cache to be given")
    end
  end

  defp get_first_config_line(true), do: "import Config"
  defp get_first_config_line(false), do: "use Mix.Config"

  embed_template(:cache, """
  defmodule <%= inspect @mod %> do
    use Nebulex.Cache,
      otp_app: <%= inspect @app %>,
      adapter: Nebulex.Adapters.Local
  end
  """)

  embed_template(:config, """
  config <%= inspect @app %>, <%= inspect @mod %>,
    # Sets :shards as backend (defaults to :ets)
    # backend: :shards,
    # GC interval for pushing a new generation (e.g., 12 hrs)
    gc_interval: :timer.hours(12),
    # Max number of entries (e.g, 1 million)
    max_size: 1_000_000,
    # Max memory size in bytes (e.g., 2GB)
    allocated_memory: 2_000_000_000,
    # GC interval for checking memory and maybe evict entries (e.g., 10 sec)
    gc_memory_check_interval: :timer.seconds(10)
  """)
end
