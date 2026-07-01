# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :food_street,
  ecto_repos: [FoodStreet.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# URL gốc của frontend, dùng để dựng link trong lời mời gửi vào Panchat.
config :food_street, :frontend_url, "https://dev.pancake.vn:3200"

# Configure the endpoint
config :food_street, FoodStreetWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FoodStreetWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FoodStreet.PubSub,
  live_view: [signing_salt: "YWwU7aeJ"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Guardian JWT configuration
config :food_street, FoodStreet.Guardian,
  issuer: "food_street",
  secret_key: "dev_only_change_me_z3Qk8rN2pL5sW9xT4vB7yE1aC6dF0gH",
  ttl: {7, :days}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
