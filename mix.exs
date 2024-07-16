defmodule Watermelon.MixProject do
  use Mix.Project

  def project do
    [
      app: :watermelon,
      description: "Super simple Gherkin features to ExUnit tests translator",
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      elixirc_options: [
        warnings_as_errors: true
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:ex_unit, :logger]
    ]
  end

  defp package do
    [
      licenses: ["MPL-2.0"],
      links: %{
        "Github" => "https://github.com/hauleth/watermelon",
        "Gherkin Reference" => "https://docs.cucumber.io/gherkin/reference/"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gherkin, "~> 1.6.0"},

      # Documentation
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev], runtime: false},

      # Development
      {:credo, ">= 0.0.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},

      # Testing
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:excoveralls, "~> 0.10", only: [:test]}
    ]
  end
end
