defmodule FoodStreet.GeminiTest do
  # async: false — vài test đụng vào Application env `:gemini_api_key` (toàn cục).
  use ExUnit.Case, async: false

  alias FoodStreet.Gemini

  # Envelope generateContent thật: candidates[0].content.parts[0].text là CHUỖI JSON.
  defp gemini_json(map) do
    %{"candidates" => [%{"content" => %{"parts" => [%{"text" => Jason.encode!(map)}]}}]}
  end

  defp stub_gemini!(fun), do: Req.Test.stub(FoodStreet.Gemini, fun)

  describe "classify/2 — decode structured output" do
    test "OUT_OF_STOCK kèm items" do
      stub_gemini!(fn conn ->
        Req.Test.json(conn, gemini_json(%{"intent" => "OUT_OF_STOCK", "items" => ["Xôi", "  "]}))
      end)

      assert {:ok, %{intent: "OUT_OF_STOCK", items: ["Xôi"]}} =
               Gemini.classify("hết xôi rồi em", %{category_name: "Ăn sáng", item_names: ["Xôi"]})
    end

    test "READY_FOR_PICKUP / PAYMENT / OTHER items rỗng" do
      for intent <- ["READY_FOR_PICKUP", "PAYMENT", "OTHER"] do
        stub_gemini!(fn conn ->
          Req.Test.json(conn, gemini_json(%{"intent" => intent, "items" => []}))
        end)

        assert {:ok, %{intent: ^intent, items: []}} = Gemini.classify("tin bất kỳ")
      end
    end

    test "intent lạ (ngoài enum) → {:error, :bad_response}" do
      stub_gemini!(fn conn ->
        Req.Test.json(conn, gemini_json(%{"intent" => "WAT", "items" => []}))
      end)

      assert {:error, :bad_response} = Gemini.classify("gì đó")
    end

    test "không có candidate (bị chặn) → {:error, :no_candidate}" do
      stub_gemini!(fn conn -> Req.Test.json(conn, %{"candidates" => []}) end)
      assert {:error, :no_candidate} = Gemini.classify("gì đó")
    end
  end

  describe "classify/2 — request payload" do
    test "gửi responseSchema (enum intent) + grounding tên món trong prompt" do
      test_pid = self()

      stub_gemini!(fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:gemini_req, conn.request_path, Jason.decode!(raw)})
        Req.Test.json(conn, gemini_json(%{"intent" => "OTHER", "items" => []}))
      end)

      assert {:ok, _} =
               Gemini.classify("còn bánh mì không", %{
                 category_name: "Ăn sáng",
                 item_names: ["Xôi", "Bánh mì"]
               })

      assert_received {:gemini_req, path, body}
      assert path =~ ":generateContent"

      schema = body["generationConfig"]["responseSchema"]
      assert schema["properties"]["intent"]["enum"] == ~w(OUT_OF_STOCK READY_FOR_PICKUP PAYMENT OTHER)
      assert body["generationConfig"]["responseMimeType"] == "application/json"

      # Tên món được nhồi vào prompt để model trả tên canonical.
      prompt = get_in(body, ["contents", Access.at(0), "parts", Access.at(0), "text"])
      assert prompt =~ "Xôi"
      assert prompt =~ "Bánh mì"
    end
  end

  describe "không cấu hình / lỗi HTTP" do
    test "thiếu key → {:error, :no_api_key}, KHÔNG gọi mạng" do
      prev = Application.get_env(:food_street, :gemini_api_key)
      Application.delete_env(:food_street, :gemini_api_key)
      on_exit(fn -> Application.put_env(:food_street, :gemini_api_key, prev) end)

      # Nếu lỡ gọi mạng, stub này sẽ nổ (fail test) vì assert sai.
      stub_gemini!(fn conn -> Req.Test.json(conn, gemini_json(%{"intent" => "OTHER"})) end)

      refute Gemini.enabled?()
      assert Gemini.classify("gì đó") == {:error, :no_api_key}
    end

    test "HTTP 5xx từ Gemini → {:error, {:gemini, \"http_500\"}}" do
      stub_gemini!(fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      assert {:error, {:gemini, "http_500"}} = Gemini.classify("gì đó")
    end

    test "lỗi transport → {:error, {:gemini, _}}" do
      stub_gemini!(fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert {:error, {:gemini, %Req.TransportError{reason: :timeout}}} = Gemini.classify("gì đó")
    end
  end
end
