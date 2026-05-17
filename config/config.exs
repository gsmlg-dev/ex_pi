import Config

config :ex_pi_web, ExPiWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "uR8T8QyHkZfTjG+lS0fWf6eQ+V8S8QyHkZfTjG+lS0fWf6eQ+V8S8QyHkZfTjG+l",
  render_errors: [
    formats: [html: ExPiWeb.ErrorHTML, json: ExPiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExPiWeb.PubSub,
  live_view: [signing_salt: "v8Lh+K6p"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
