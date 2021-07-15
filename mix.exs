defmodule Versioned.MixProject do
  use Mix.Project

  def project do
    [
      app: :versioned,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      preferred_cli_env: [ci: :test],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        ignore: ".dialyzer_ignore.exs"
      ],

      # Docs
      name: "Versioned",
      source_url: "https://github.com/instinctscience/versioned",
      homepage_url: "https://github.com/instinctscience/versioned",
      docs: [
        main: "Versioned",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.3"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:postgrex, "~> 0.15", only: [:test]}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      ci: ["lint", "test", "dialyzer"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      lint: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo"
      ]
    ]
  end

  defp description do
    "Maintain an immutable history for Ecto.Schema records."
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/instinctscience/versioned"}
    ]
  end
end
