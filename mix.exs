defmodule ChurchBands.MixProject do
  use Mix.Project

  def project do
    [
      app: :church_bands,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ChurchBands.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.5"},
      {:bcrypt_elixir, "~> 3.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      # Mede a cobertura da suíte por arquivo e reprova o que ficar abaixo do
      # mínimo configurado em `coveralls.json`.
      {:excoveralls, "~> 0.18", only: :test},
      # As três análises que o `precommit` roda junto com os testes (R-18).
      # Ficam também em `:test` porque é nesse ambiente que o alias roda.
      # `credo` opina sobre consistência e complexidade, `sobelow` é análise de
      # segurança específica de Phoenix e `mix_audit` procura CVE conhecida nas
      # dependências.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      # Só de desenvolvimento: `mix salad.install` copiou os componentes para
      # `lib/church_bands_web/components/ui/`, então nada em runtime referencia
      # o módulo `SaladUI`. Deixá-la em produção arrastaria o `igniter` e mais
      # cinco pacotes de ferramenta de código para dentro do release.
      {:salad_ui, "~> 1.0.0", only: :dev, runtime: false},
      # Esta, sim, é de runtime: `TwMerge.Cache` está na árvore de supervisão e
      # `TwMerge.merge/1` resolve as classes de todo componente.
      {:tw_merge, "~> 0.1"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind church_bands", "esbuild church_bands"],
      "assets.deploy": [
        "tailwind church_bands --minify",
        "esbuild church_bands --minify",
        "phx.digest"
      ],
      # `coveralls` roda a suíte pelo alias `test` acima (com o banco criado e
      # migrado) e ainda reprova o que ficar abaixo do mínimo de cobertura
      # configurado em `coveralls.json` — por isso ele entra no lugar de `test`,
      # e não depois dele: rodar a suíte duas vezes não diria nada a mais.
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        # As três análises entram antes da suíte porque são rápidas e o que
        # elas acham não depende de teste nenhum: `credo` opina sobre
        # consistência e complexidade, `sobelow` procura falha de segurança de
        # Phoenix e `deps.audit` procura CVE conhecida nas dependências (R-18).
        "credo --strict",
        "sobelow --exit",
        "deps.audit",
        "coveralls"
      ]
    ]
  end
end
