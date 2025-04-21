defmodule Nebulex.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-nebulex/nebulex"
  @version "3.0.0-dev"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),

      # Testing
      test_coverage: [tool: ExCoveralls, export: "test-coverage"],
      preferred_cli_env: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Dialyzer
      dialyzer: dialyzer(),

      # Hex
      description: "In-memory and distributed caching toolkit for Elixir",
      package: package(),

      # Docs
      name: "Nebulex",
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/dialyzer"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:eex],
      mod: {Nebulex.Application, []}
    ]
  end

  defp deps do
    [
      # Required
      {:nimble_options, "~> 0.5 or ~> 1.0"},

      # Optional
      {:decorator, "~> 1.4", optional: true},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true},

      # Test & Code Analysis
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.2", only: [:dev, :test]},
      {:mimic, "~> 1.11", only: :test},
      {:doctor, "~> 0.22", only: [:dev, :test]},

      # Benchmark Test
      {:benchee, "~> 1.4", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},

      # Docs
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      {:makeup_diff, "~> 0.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "coveralls.html",
        "sobelow --skip --exit Low",
        "dialyzer --format short",
        "doctor"
      ]
    ]
  end

  defp package do
    [
      name: :nebulex,
      maintainers: ["Carlos Bolanos"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "Nebulex",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/nebulex",
      source_url: @source_url,
      extra_section: "GUIDES",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_docs: [
        # Caching decorators
        group_for_function("Decorator API"),
        group_for_function("Decorator Helpers"),
        group_for_function("Internal API"),

        # Cache API
        group_for_function("User callbacks"),
        group_for_function("Runtime API"),
        group_for_function("KV API"),
        group_for_function("Query API"),
        group_for_function("Transaction API"),
        group_for_function("Info API"),
        group_for_function("Observable API")
      ],
      groups_for_modules: [
        # Nebulex,
        # Nebulex.Cache,
        # Nebulex.Event,
        # Nebulex.Event.CacheEntryEvent,

        "Caching decorators": [
          Nebulex.Caching,
          Nebulex.Caching.Decorators,
          Nebulex.Caching.Decorators.Context
        ],
        "Adapter specification": [
          Nebulex.Adapter,
          Nebulex.Adapter.KV,
          Nebulex.Adapter.Queryable,
          Nebulex.Adapter.Transaction,
          Nebulex.Adapter.Info,
          Nebulex.Adapter.Observable
        ],
        "Built-in adapters": [
          Nebulex.Adapters.Nil,
          Nebulex.Adapters.Nil.Options
        ],
        "Built-in info implementation": [
          Nebulex.Adapters.Common.Info,
          Nebulex.Adapters.Common.Info.Stats
        ],
        "Telemetry handlers": [
          Nebulex.Telemetry.CacheEntryHandler,
          Nebulex.Telemetry.CacheStatsCounterHandler
        ],
        Utilities: [
          Nebulex.Telemetry,
          Nebulex.Time,
          Nebulex.Utils
        ]
      ]
    ]
  end

  defp extras do
    [
      # Introduction
      "guides/introduction/getting-started.md",
      "guides/introduction/nbx-adapters.md",

      # Learning
      "guides/learning/cache-usage-patterns.md",
      "guides/learning/info-api.md",
      "guides/learning/telemetry.md",
      "guides/learning/creating-new-adapter.md",

      # Upgrading
      "guides/upgrading/v3.0.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r{guides/introduction/[^\/]+\.md},
      Learning: ~r{guides/learning/[^\/]+\.md},
      Upgrading: ~r{guides/upgrading/.*}
    ]
  end

  defp group_for_function(group), do: {String.to_atom(group), &(&1[:group] == group)}

  defp dialyzer do
    [
      plt_add_apps: [:mix, :telemetry, :ex_unit],
      plt_file: {:no_warn, "priv/plts/" <> plt_file_name()},
      flags: [
        :unmatched_returns,
        :error_handling,
        :no_opaque,
        :unknown,
        :no_return
      ]
    ]
  end

  defp plt_file_name do
    "dialyzer-#{Mix.env()}-#{System.otp_release()}-#{System.version()}.plt"
  end
end
