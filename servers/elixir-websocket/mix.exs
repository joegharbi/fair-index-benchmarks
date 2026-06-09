defmodule FairIndex.MixProject do
  use Mix.Project

  def project do
    [
      app: :fair_index,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: true,
      deps: [],
      releases: [fair_index: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [
      extra_applications: [:crypto],
      mod: {FairIndex.Application, []}
    ]
  end
end
