defmodule FoodStreetWeb.PancakeWebhookControllerTest do
  use FoodStreetWeb.ConnCase, async: false

  alias FoodStreet.{Catalog, PancakeWebhookEvent, Repo}

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

  test "POST tin nhà bán chờ hết debounce rồi mới gọi Gemini", %{conn: conn} do
    Req.Test.set_req_test_to_shared()

    {:ok, _category} =
      Catalog.create_category(%{
        name: "Ăn sáng webhook",
        pancake_page_id: "page-webhook",
        pancake_conversation_id: "conv-webhook",
        pancake_page_access_token: "token"
      })

    test_pid = self()

    Req.Test.stub(FoodStreet.Gemini, fn req_conn ->
      send(test_pid, :gemini_called)

      Req.Test.json(req_conn, %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [%{"text" => Jason.encode!(%{"intent" => "OTHER", "items" => []})}]
            }
          }
        ]
      })
    end)

    Req.Test.stub(FoodStreet.Panchat, fn req_conn ->
      send(test_pid, :panchat_called)
      Req.Test.json(req_conn, %{"success" => true})
    end)

    payload = %{
      "event_type" => "messaging",
      "page_id" => "page-webhook",
      "data" => %{
        "conversation" => %{"id" => "conv-webhook", "type" => "INBOX"},
        "message" => %{
          "id" => "msg-webhook",
          "message" => "hết",
          "original_message" => "hết",
          "from" => %{"id" => "seller-webhook"}
        }
      }
    }

    conn = post(conn, ~p"/api/webhooks/pancake/#{@secret}", payload)
    assert response(conn, 200)

    refute_receive :gemini_called, 50
    assert_receive :gemini_called, 500
    assert_receive :panchat_called, 500
    assert_processed("msg-webhook")
  end

  defp assert_processed(message_id, attempts \\ 20)

  defp assert_processed(_message_id, 0), do: flunk("webhook batch did not finish")

  defp assert_processed(message_id, attempts) do
    case Repo.get_by(PancakeWebhookEvent, message_id: message_id) do
      nil ->
        Process.sleep(10)
        assert_processed(message_id, attempts - 1)

      _event ->
        :ok
    end
  end
end
