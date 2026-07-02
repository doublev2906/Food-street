defmodule FoodStreet.OrderScheduler do
  @moduledoc """
  Ticker chạy nền cho lịch hẹn tự động mở đợt đặt món (`FoodStreet.Scheduling`).

  Cứ mỗi `interval_ms` (mặc định 60s) gọi `Scheduling.run_tick/0`. Lỗi 1 nhịp được
  log và nuốt để không làm chết tiến trình. Giả định deploy 1 instance.
  """
  use GenServer
  require Logger

  alias FoodStreet.Scheduling

  @default_interval_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, config_interval())
    schedule_tick(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, %{interval: interval} = state) do
    try do
      Scheduling.run_tick()
    rescue
      e -> Logger.error("[OrderScheduler] tick lỗi: #{Exception.message(e)}")
    end

    try do
      FoodStreet.BalanceReport.run_tick()
    rescue
      e -> Logger.error("[OrderScheduler] báo số dư lỗi: #{Exception.message(e)}")
    end

    schedule_tick(interval)
    {:noreply, state}
  end

  defp schedule_tick(interval), do: Process.send_after(self(), :tick, interval)

  defp config_interval do
    :food_street
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
