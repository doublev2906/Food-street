defmodule FoodStreetWeb.Admin.StatsController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Stats

  action_fallback FoodStreetWeb.FallbackController

  def summary(conn, params) do
    date =
      case params["date"] && Date.from_iso8601(params["date"]) do
        {:ok, d} -> d
        _ -> Date.utc_today()
      end

    json(conn, %{data: Stats.summary(date)})
  end

  def revenue(conn, params) do
    today = Date.utc_today()
    from = parse_date(params["from"], Date.add(today, -7))
    to = parse_date(params["to"], today)
    json(conn, %{data: Stats.revenue_by_day(from, to)})
  end

  @doc "Thống kê tổng hợp theo khoảng ngày (ngày / tháng / năm)."
  def period(conn, params) do
    today = Date.utc_today()
    from = parse_date(params["from"], today)
    to = parse_date(params["to"], today)
    json(conn, %{data: Stats.period_summary(from, to)})
  end

  defp parse_date(nil, default), do: default

  defp parse_date(str, default) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> default
    end
  end
end
