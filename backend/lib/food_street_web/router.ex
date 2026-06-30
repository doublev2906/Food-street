defmodule FoodStreetWeb.Router do
  use FoodStreetWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug FoodStreetWeb.Auth.Pipeline
  end

  pipeline :admin do
    plug FoodStreetWeb.Plugs.RequireAdmin
  end

  # Public — không cần đăng nhập
  scope "/api", FoodStreetWeb do
    pipe_through :api

    post "/login", AuthController, :login
    get "/health", HealthController, :index
  end

  # Yêu cầu đăng nhập (user hoặc admin)
  scope "/api", FoodStreetWeb do
    pipe_through [:api, :auth]

    get "/me", AuthController, :me

    get "/menu", MenuController, :index

    get "/orders", OrderController, :index
    post "/orders", OrderController, :create
    delete "/orders/:id", OrderController, :cancel

    get "/fund/balance", FundController, :balance
    get "/fund/transactions", FundController, :transactions
  end

  # Khu vực admin
  scope "/api/admin", FoodStreetWeb.Admin do
    pipe_through [:api, :auth, :admin]

    resources "/users", UserController, except: [:new, :edit]

    get "/menu", MenuController, :index
    post "/menu", MenuController, :create
    put "/menu/:id", MenuController, :update
    delete "/menu/:id", MenuController, :delete

    get "/orders", OrderController, :index
    post "/orders/:id/confirm", OrderController, :confirm
    post "/orders/confirm_date", OrderController, :confirm_date

    get "/stats", StatsController, :summary
    get "/stats/revenue", StatsController, :revenue

    get "/fund/transactions", FundController, :index
    post "/fund/deposit", FundController, :deposit
    post "/fund/adjust", FundController, :adjust
  end
end
