defmodule Mix.Tasks.Nbx.Gen.CacheTest do
  use ExUnit.Case

  import Mix.Tasks.Nbx.Gen.Cache, only: [run: 1]

  describe "nbx.gen.cache" do
    test "generates a new cache" do
      in_tmp("new_cache", fn ->
        run(["-c", "Cache"])

        assert_file("lib/cache.ex", """
        defmodule Cache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Local
        end
        """)

        first_line = if Code.ensure_loaded?(Config), do: "import Config", else: "use Mix.Config"

        assert_file("config/config.exs", """
        #{first_line}

        #{config_template()}
        """)
      end)
    end

    test "generates a new cache with existing config file" do
      in_tmp("existing_config", fn ->
        File.mkdir_p!("config")

        File.write!("config/config.exs", """
        import Config
        """)

        run(["-c", "Cache"])

        assert_file("config/config.exs", """
        import Config

        #{config_template()}
        """)
      end)
    end

    test "generates a new cache with existing old config file" do
      in_tmp("existing_config", fn ->
        File.mkdir_p!("config")

        File.write!("config/config.exs", """
        # Hello
        use Mix.Config
        # World
        """)

        run(["-c", "Cache"])

        assert_file("config/config.exs", """
        # Hello
        use Mix.Config

        #{config_template()}
        """)
      end)
    end

    test "generates a new namespaced cache" do
      in_tmp("namespaced", fn ->
        run(["-c", "MyApp.Cache"])
        assert_file("lib/my_app/cache.ex", "defmodule MyApp.Cache do")
      end)
    end

    test "raises exception because missing option -c" do
      msg = "nbx.gen.cache expects the cache to be given as -c MyApp.Cache"

      assert_raise Mix.Error, msg, fn ->
        run([])
      end
    end

    test "raises exception because multiple options -c" do
      msg = "nbx.gen.cache expects a single cache to be given"

      assert_raise Mix.Error, msg, fn ->
        run(["-c", "Cache1", "-c", "Cache2"])
      end
    end
  end

  ## Private Functions

  @tmp_path Path.expand("../../../tmp", __DIR__)

  defp in_tmp(path, fun) do
    path = Path.join(@tmp_path, path)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    File.cd!(path, fun)
  end

  defp assert_file(file, match) do
    assert File.read!(file) =~ match
  end

  defp config_template do
    """
    config :nebulex, Cache,
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
    """
    |> String.trim_trailing()
  end
end
