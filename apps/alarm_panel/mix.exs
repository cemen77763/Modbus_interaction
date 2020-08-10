defmodule AlarmPanel.MixProject do
    use Mix.Project

    def project do
        [
        app: :alarm_panel,
        version: "1.0.0",
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock",
        language: :erlang,
        start_permanent: Mix.env() == :prod,
        deps: deps()
        ]
    end

    # Run "mix help compile.app" to learn about applications.
    def application do
        [
        mod: {:alarm_panel_app, []},
        registered: [:alarm_panel, :alarm_panel_app],
        description: ['Application to interact with modbus TCP devices'],
        licenses: ['Apache 2.0'],
        included_applications: [:gen_modbus_s]
        ]
    end

    # Run "mix help deps" to learn about dependencies.
    defp deps do
        [
        # {:dep_from_hexpm, "~> 0.3.0"},
        # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
        # {:sibling_app_in_umbrella, in_umbrella: true}
        {:gen_modbus_s, in_umbrella: true}
        ]
    end
end
