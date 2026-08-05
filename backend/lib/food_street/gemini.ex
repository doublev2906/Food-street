defmodule FoodStreet.Gemini do
  @moduledoc """
  Phân loại ý định tin phản hồi của **nhà bán** bằng Google Gemini
  (`generateContent`, structured JSON output).

  Dùng cho `FoodStreet.PancakeInbound`: thay vì relay nguyên văn mọi tin nhà bán,
  ta hỏi Gemini xem tin đó là **hết món** / **báo xuống lấy hàng** / **báo thanh
  toán** / **khác**, rồi hành động phù hợp (ping người đổi món, ping người đi lấy
  hàng, hoặc nhắc admin chuyển khoản).

      POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent
      x-goog-api-key: <GEMINI_API_KEY>
      body: %{contents, systemInstruction, generationConfig{responseSchema, ...}}

  Key lấy từ env `GEMINI_API_KEY` (xem `config/runtime.exs`), KHÔNG hardcode. Chưa
  cấu hình key → `enabled?/0` trả `false` và `classify/2` trả `{:error, :no_api_key}`
  (không gọi mạng) để caller fallback relay như cũ.

  Mọi lỗi (thiếu key, timeout, HTTP lỗi, response lạ) đều trả `{:error, reason}`
  mềm — caller tự fallback, không raise.
  """

  require Logger

  @base_url "https://generativelanguage.googleapis.com"
  @default_model "gemini-2.5-flash-lite"

  # Các ý định model được phép trả — PHẢI khớp hệt các nhánh `dispatch` ở PancakeInbound.
  @intents ["OUT_OF_STOCK", "READY_FOR_PICKUP", "PAYMENT", "OTHER"]

  @system_instruction """
  Bạn phân loại tin nhắn CỦA NGƯỜI BÁN đồ ăn trả lời cho nhóm đặt cơm/đồ ăn.
  Chọn đúng 1 ý định:
  - OUT_OF_STOCK: người bán báo HẾT MÓN hoặc hết nguyên liệu, đề nghị đổi món.
  - READY_FOR_PICKUP: người bán báo đồ đã xong, mời XUỐNG/QUA LẤY HÀNG.
  - PAYMENT: người bán báo tiền, gửi số tài khoản, nhắc CHUYỂN KHOẢN/THANH TOÁN.
  - OTHER: chào hỏi, xác nhận đã nhận đơn, hoặc không rõ.

  Nếu là OUT_OF_STOCK, điền vào "items" TÊN CÁC MÓN bị hết. Chỉ dùng tên món có
  trong danh sách món đã đặt được cung cấp (khớp chính xác chuỗi trong danh sách
  đó); không có món nào khớp thì để "items" rỗng. Các ý định khác luôn để "items" rỗng.
  """

  @doc """
  Phân loại `text` (tin nhà bán) trong ngữ cảnh 1 đợt đặt: `ctx` gồm
  `:category_name` và `:item_names` (danh sách tên món đã đặt, để grounding).

  Trả `{:ok, %{intent: intent, items: [String.t()]}}` với `intent` ∈
  #{inspect(@intents)}, hoặc `{:error, reason}` khi thiếu key / lỗi mạng / response lạ.
  """
  def classify(text, ctx \\ %{}) when is_binary(text) do
    with {:ok, key} <- api_key() do
      request(key, text, ctx)
    end
  end

  defp request(key, text, ctx) do
    url = "#{@base_url}/v1beta/models/#{model()}:generateContent"

    opts =
      [
        json: body(text, ctx),
        headers: [{"x-goog-api-key", key}],
        receive_timeout: 8_000,
        retry: false
      ] ++ Application.get_env(:food_street, :gemini_req_options, [])

    case Req.post(url, opts) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        parse(resp)

      {:ok, %{status: status, body: resp}} ->
        Logger.warning("[Gemini] HTTP #{status}: #{inspect(resp)}")
        {:error, {:gemini, "http_#{status}"}}

      {:error, reason} ->
        Logger.warning("[Gemini] lỗi kết nối: #{inspect(reason)}")
        {:error, {:gemini, reason}}
    end
  end

  # Dựng body generateContent với structured JSON output (responseSchema).
  defp body(text, ctx) do
    %{
      "systemInstruction" => %{"parts" => [%{"text" => @system_instruction}]},
      "contents" => [%{"role" => "user", "parts" => [%{"text" => prompt(text, ctx)}]}],
      "generationConfig" => %{
        "temperature" => 0,
        "responseMimeType" => "application/json",
        "responseSchema" => %{
          "type" => "OBJECT",
          "properties" => %{
            "intent" => %{"type" => "STRING", "enum" => @intents},
            "items" => %{"type" => "ARRAY", "items" => %{"type" => "STRING"}}
          },
          "required" => ["intent", "items"]
        }
      }
    }
  end

  defp prompt(text, ctx) do
    category = Map.get(ctx, :category_name) || "?"
    item_names = Map.get(ctx, :item_names, [])

    items_block =
      case item_names do
        [] -> "(chưa có đơn nào)"
        names -> Enum.map_join(names, "\n", &"- #{&1}")
      end

    """
    Danh mục: #{category}
    Các món đã đặt trong đợt hiện tại:
    #{items_block}

    Tin nhắn của người bán:
    "#{text}"
    """
  end

  # candidates[0].content.parts[0].text là CHUỖI JSON (do responseMimeType) -> decode.
  defp parse(%{"candidates" => [cand | _]}) do
    with %{"content" => %{"parts" => [%{"text" => json} | _]}} <- cand,
         {:ok, %{"intent" => intent} = decoded} when intent in @intents <- Jason.decode(json) do
      {:ok, %{intent: intent, items: normalize_items(decoded["items"])}}
    else
      _ ->
        Logger.warning("[Gemini] response không phân tích được: #{inspect(cand)}")
        {:error, :bad_response}
    end
  end

  defp parse(resp) do
    # candidates rỗng (bị chặn SAFETY...) hoặc shape lạ.
    Logger.warning("[Gemini] không có candidate: #{inspect(resp)}")
    {:error, :no_candidate}
  end

  defp normalize_items(items) when is_list(items) do
    items
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_items(_), do: []

  @doc "Đã cấu hình key Gemini chưa (dùng để caller quyết định gọi hay relay thẳng)."
  def enabled?, do: match?({:ok, _}, api_key())

  defp api_key do
    case Application.get_env(:food_street, :gemini_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :no_api_key}
    end
  end

  defp model, do: Application.get_env(:food_street, :gemini_model, @default_model)
end
