defmodule FoodStreet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        FoodStreetWeb.Telemetry,
        FoodStreet.Repo,
        {DNSCluster, query: Application.get_env(:food_street, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FoodStreet.PubSub}
      ] ++
        scheduler_children() ++
        [
          # Start to serve requests, typically the last entry
          FoodStreetWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FoodStreet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Ticker lịch hẹn tự động mở đợt đặt món — chỉ bật khi cấu hình cho phép
  # (tắt trong môi trường test để không tự chạy).
  defp scheduler_children do
    if Application.get_env(:food_street, FoodStreet.OrderScheduler, [])[:enabled] do
      [FoodStreet.OrderScheduler]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FoodStreetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
