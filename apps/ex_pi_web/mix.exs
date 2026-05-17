defmodule ExPiWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_pi_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ExPiWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_live_view, "~> 1.0.0-rc.6"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:gettext, "~> 0.20"},
      {:ex_pi_agent, in_umbrella: true},
      {:ex_pi_session, in_umbrella: true},
      {:floki, ">= 0.30.0", only: :test}
    ]
  end
end
