defmodule ModbusInteraction.MixProject do
    use Mix.Project

    def project do
        [
        app: :modbus_interaction,
        version: "1.2.5",
        language: :erlang,
        start_permanent: Mix.env() == :prod,
        deps: deps()]
    end

    # Run "mix help compile.app" to learn about applications.
    def application do
      [
        mod: {:modbus_interaction_app, []},
        registered: [:modbus_gen],
        description: ['Application to interact with modbus TCP devices'],
        licenses: ['Apache 2.0']]
    end

    # Run "mix help deps" to learn about dependencies.
    defp deps do
      [
        # {:dep_from_hexpm, "~> 0.3.0"},
        # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      ]
    end
end
