defmodule FoodStreet.PancakePage do
  @moduledoc """
  Gửi tin cho **nhà bán** qua Pancake Page API (pages.fm) — KHÁC với
  `FoodStreet.Panchat` (chat nội bộ pancakework.vn).

  Mỗi danh mục (`Catalog.Category`) cấu hình sẵn `pancake_page_id`,
  `pancake_conversation_id` và `pancake_page_access_token` của page nhà bán. Khi admin
  bấm "Gửi đơn cho nhà bán", ta đẩy nội dung đơn gộp vào conversation đó:

      POST https://pages.fm/api/public_api/v1/pages/{page_id}/conversations/{conversation_id}/messages
      ?page_access_token=<TOKEN>
      body: %{action: "reply_inbox", message: "<nội dung đơn>"}

  Lưu ý: Pancake Page xác thực bằng **query param** `page_access_token` (không phải
  header Bearer). Trả `{:ok, body}` khi HTTP 2xx và body `success == true`.
  """

  require Logger

  alias FoodStreet.Catalog.Category

  @base_url "https://pages.fm/api/public_api/v1"

  @doc """
  Gửi nội dung đơn `message` cho nhà bán của `category`. Guard trước cấu hình:
  thiếu page_id/conversation_id/token -> `{:error, :pancake_not_configured}`.
  """
  def send_order(%Category{} = category, message) when is_binary(message) do
    if Category.pancake_configured?(category) do
      post_message(
        category.pancake_page_id,
        category.pancake_conversation_id,
        category.pancake_page_access_token,
        message
      )
    else
      {:error, :pancake_not_configured}
    end
  end

  @doc """
  Gửi 1 tin `reply_inbox` vào conversation của page. Tách ra để test thuần.
  Thành công khi HTTP 2xx và body có `"success" => true`.
  """
  def post_message(page_id, conversation_id, token, message) do
    url = "#{@base_url}/pages/#{page_id}/conversations/#{conversation_id}/messages"
    IO.inspect(url, label: "Pancake Page gửi tin tới URL")

    # `:pancake_req_options` cho phép test tiêm Req.Test plug thay vì gọi mạng thật.
    opts =
      [
        params: [page_access_token: token],
        json: %{"action" => "reply_inbox", "message" => message},
        receive_timeout: 10_000
      ] ++ Application.get_env(:food_street, :pancake_req_options, [])

    IO.inspect(opts, label: "Pancake Page gửi tin với opts")

    case Req.post(url, opts) do
      {:ok, %{status: status, body: %{"success" => true} = body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Pancake Page trả về lỗi (#{status}): #{inspect(body)}")
        {:error, {:pancake, "http_#{status}"}}

      {:error, reason} ->
        Logger.warning("Pancake Page lỗi kết nối: #{inspect(reason)}")
        {:error, {:pancake, reason}}
    end
  end
end
