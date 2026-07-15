defmodule FoodStreetWeb.PancakeWebhookControllerTest do
  use FoodStreetWeb.ConnCase, async: true

  # Khớp config/test.exs :pancake_webhook_secret
  @secret "test_webhook_secret"

  test "POST đúng secret → 200", %{conn: conn} do
    # event_type != "messaging" -> handle_messaging short-circuit, không đụng DB/HTTP.
    conn = post(conn, ~p"/api/webhooks/pancake/#{@secret}", %{"event_type" => "post"})
    assert response(conn, 200)
  end

  test "POST sai secret → 401", %{conn: conn} do
    conn = post(conn, ~p"/api/webhooks/pancake/sai-secret", %{"event_type" => "post"})
    assert response(conn, 401)
  end
end
