defmodule DeltaCrdt.MixProject do
  use Mix.Project

  def project do
    [
      app: :delta_crdt,
      version: "0.1.10",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      package: package(),
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
      {:benchee, ">= 0.0.0", only: :dev, runtime: false},
      {:exprof, "~> 0.2.0", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
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
end
