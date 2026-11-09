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
    # Xoá cookie xem trang /share (token chính nằm ở localStorage, frontend tự xoá).
    post "/logout", AuthController, :logout
    get "/health", HealthController, :index

    # Webhook Pancake Page (nhà bán trả lời) — bảo vệ bằng secret trong URL.
    post "/webhooks/pancake/:secret", PancakeWebhookController, :messaging
  end

  # Trang HTML chia sẻ (Caddy proxy /share/* sang đây). Trình duyệt mở link trực tiếp
  # (Accept: text/html) nên không qua pipeline :api; xác thực bằng cookie fs_share.
  scope "/", FoodStreetWeb do
    get "/share/*path", ShareController, :show
  end

  # Lưu dữ liệu người xem nhập trên trang /share — gọi từ trang sandbox (origin null),
  # body text/plain, xác thực bằng token nhúng trong trang.
  scope "/api", FoodStreetWeb do
    post "/share_state", ShareStateController, :save
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

    # Tình trạng nợ (gốc + lãi) của chính user
    get "/interest/me", InterestController, :me
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
    post "/group_orders/:id/reopen", GroupOrderController, :reopen
    post "/group_orders/:id/cancel", GroupOrderController, :cancel
    post "/group_orders/:id/send_to_seller", GroupOrderController, :send_to_seller
    # Tick tay "đã thanh toán cho người bán" (issue #10)
    put "/group_orders/:id/seller_paid", GroupOrderController, :set_seller_paid

    get "/orders", OrderController, :index
    post "/orders/:id/confirm", OrderController, :confirm
    put "/orders/:id", OrderController, :update

    get "/stats", StatsController, :summary
    get "/stats/revenue", StatsController, :revenue
    get "/stats/by_category", StatsController, :by_category
    get "/stats/period", StatsController, :period

    get "/fund/transactions", FundController, :index
    post "/fund/deposit", FundController, :deposit
    post "/fund/adjust", FundController, :adjust

    # Quỹ lãi trên số dư âm (tính lãi kép theo ngày)
    get "/interest/fund", InterestController, :fund
    get "/interest/charges", InterestController, :index
    post "/interest/run", InterestController, :run

    # Mua đồ ăn ngoài menu — chia tiền cho người ăn
    get "/external_purchases", ExternalPurchaseController, :index
    post "/external_purchases", ExternalPurchaseController, :create

    # Cấu hình hệ thống (Panchat token)
    get "/settings/panchat", SettingsController, :show
    put "/settings/panchat", SettingsController, :update

    # Lịch hẹn tự động mở đợt đặt món hằng ngày (dùng chung)
    get "/order_schedule", OrderScheduleController, :show
    put "/order_schedule", OrderScheduleController, :update

    # Trang HTML chia sẻ (serve công khai ở /share/<tên file> qua Caddy)
    # ?dir=a/b — đường dẫn thư mục tương đối trong share/ (trống = gốc)
    get "/shared_pages", SharedPageController, :index
    post "/shared_pages", SharedPageController, :create
    post "/shared_pages/folders", SharedPageController, :create_folder
    # ?path=a/b/c.html — xoá file hoặc cả thư mục
    delete "/shared_pages", SharedPageController, :delete
  end
end
