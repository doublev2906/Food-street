defmodule FoodStreetWeb.Auth.Pipeline do
  @moduledoc "Pipeline xác thực: yêu cầu JWT hợp lệ trong header Authorization."
  use Guardian.Plug.Pipeline,
    otp_app: :food_street,
    module: FoodStreet.Guardian,
    error_handler: FoodStreetWeb.Auth.ErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
end
