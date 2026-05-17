import Config

config :ex_pi_web, ExPiWeb.Endpoint,
  http: [port: 4002],
  server: false

config :logger, level: :warning
