# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :church_bands,
  ecto_repos: [ChurchBands.Repo],
  generators: [timestamp_type: :utc_datetime]

# Os erros de formulário dos componentes SaladUI passam pelo gettext do projeto,
# como os do resto da aplicação. A chave é lida em
# `ChurchBandsWeb.Components.UI.Helpers`, que a busca em `:church_bands` — e não
# em `:salad_ui`, que é dependência só de desenvolvimento.
config :church_bands,
       :error_translator_function,
       {ChurchBandsWeb.CoreComponents, :translate_error}

# A aplicação fala português. Sem isso o gettext assume `en` e toda validação
# sem `message:` explícito chega à tela em inglês (DT-1) — as traduções vivem em
# `priv/gettext/pt_BR`.
config :church_bands, ChurchBandsWeb.Gettext,
  default_locale: "pt_BR",
  allowed_locales: ~w(pt_BR)

# Configure the endpoint
config :church_bands, ChurchBandsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ChurchBandsWeb.ErrorHTML, json: ChurchBandsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ChurchBands.PubSub,
  live_view: [signing_salt: "Cplu5Pg6"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :church_bands, ChurchBands.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  church_bands: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  church_bands: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
