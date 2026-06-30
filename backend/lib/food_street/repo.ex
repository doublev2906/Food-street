defmodule FoodStreet.Repo do
  use Ecto.Repo,
    otp_app: :food_street,
    adapter: Ecto.Adapters.Postgres
end
