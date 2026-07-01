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
    put "/profile", ProfileController, :update
    put "/password", ProfileController, :change_password

    get "/menu", MenuController, :index

    # Đợt đặt nhóm (user)
    get "/group_orders", GroupOrderController, :index
    get "/group_orders/:id", GroupOrderController, :show
    post "/group_orders/:id/order", GroupOrderController, :create_order

    get "/orders", OrderController, :index
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

    # Danh mục món
    get "/categories", CategoryController, :index
    post "/categories", CategoryController, :create
    put "/categories/:id", CategoryController, :update
    delete "/categories/:id", CategoryController, :delete

    # Đợt đặt nhóm
    get "/group_orders", GroupOrderController, :index
    get "/group_orders/:id", GroupOrderController, :show
    post "/group_orders", GroupOrderController, :create
    put "/group_orders/:id", GroupOrderController, :update
    delete "/group_orders/:id", GroupOrderController, :delete
    post "/group_orders/:id/close", GroupOrderController, :close

    get "/orders", OrderController, :index
    post "/orders/:id/confirm", OrderController, :confirm

    get "/stats", StatsController, :summary
    get "/stats/revenue", StatsController, :revenue

    get "/fund/transactions", FundController, :index
    post "/fund/deposit", FundController, :deposit
    post "/fund/adjust", FundController, :adjust

    # Cấu hình hệ thống (Panchat token)
    get "/settings/panchat", SettingsController, :show
    put "/settings/panchat", SettingsController, :update

    # Lịch hẹn tự động mở đợt đặt món hằng ngày (dùng chung)
    get "/order_schedule", OrderScheduleController, :show
    put "/order_schedule", OrderScheduleController, :update
  end
end
