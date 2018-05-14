defmodule DeltaCrdt.MixProject do
  use Mix.Project

  def project do
    [
      app: :delta_crdt,
      version: "0.1.0",
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
    []
  end

  defp package do
    [
      name: "Delta CRDT",
      licenses: ["MIT"],
      maintainers: ["Derek Kraan"],
      links: [
        github: "https://github.com/derekkraan/delta_crdt_ex"
      ]
    ]
  end
end
