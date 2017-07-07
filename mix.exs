defmodule Cachex.Mixfile do
  use Mix.Project

  @url_docs "http://hexdocs.pm/cachex"
  @url_github "https://github.com/zackehh/cachex"

  def project do
    [
      app: :cachex,
      name: "Cachex",
      description: "Powerful in-memory key/value storage for Elixir",
      package: %{
        files: [
          "lib",
          "mix.exs",
          "LICENSE"
        ],
        licenses: [ "MIT" ],
        links: %{
          "Docs" => @url_docs,
          "GitHub" => @url_github
        },
        maintainers: [ "Isaac Whitfield" ]
      },
      version: "2.1.0",
      elixir: "~> 1.2",
      deps: deps(),
      docs: [
        source_ref: "master",
        source_url: @url_github,
        main: "getting-started",
        extras: [
          "docs/getting-started.md",
          "docs/action-blocks.md",
          "docs/cache-limits.md",
          "docs/custom-commands.md",
          "docs/disk-interaction.md",
          "docs/execution-hooks.md",
          "docs/fallback-caching.md",
          "docs/ttl-implementation.md",
          "docs/migrating-to-v2.x.md"
        ]
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        "cachex": :test
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger, :eternal],
      mod: {Cachex.Application, []}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      # Production dependencies
      { :eternal, "~> 1.1" },
      # Local dependencies
      { :benchfella,  "~> 0.3", optional: true, only: [ :dev, :test ] },
      { :bmark,       "~> 1.0", optional: true, only: [ :dev, :test ] },
      { :credo,       "~> 0.8", optional: true, only: [ :dev, :test ] },
      { :ex_doc,      ex_doc(), optional: true, only: [ :dev, :test ] },
      { :excoveralls, "~> 0.7", optional: true, only: [ :dev, :test ] },
      { :exprof,      "~> 0.2", optional: true, only: [ :dev, :test ] }
    ]
  end

  # Determine an :ex_doc version compatible with old Elixir versions,
  # as it's incompatible with Elixir v1.2 from v0.16 onwards.
  defp ex_doc do
    case Version.compare(System.version(), "1.3.0") do
      :lt ->  "~> 0.15"
      :gt ->  "~> 0.16"
    end
  end
end
