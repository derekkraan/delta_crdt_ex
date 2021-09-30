defmodule DeltaCrdt.MixProject do
  use Mix.Project

  def project do
    [
      app: :delta_crdt,
      version: "0.6.4",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      source_url: "https://github.com/derekkraan/delta_crdt_ex",
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:benchee, ">= 0.0.0", only: :dev, runtime: false},
      {:benchee_html, ">= 0.0.0", only: :dev, runtime: false},
      {:exprof, "~> 0.2.0", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:merkle_map, "~> 0.2.0"},
      {:stream_data, "~> 0.4", only: :test}
    ]
  end

  defp package do
    [
      name: "delta_crdt",
      description: "Implementations of δ-CRDTs",
      licenses: ["MIT"],
      maintainers: ["Derek Kraan"],
      links: %{GitHub: "https://github.com/derekkraan/delta_crdt_ex"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
