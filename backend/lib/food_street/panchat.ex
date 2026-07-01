defmodule FoodStreet.Panchat do
  @moduledoc """
  Gửi tin nhắn vào Panchat (pancakework.vn).

  Dùng để báo cho cả nhóm khi admin mở 1 đợt đặt đồ ăn sáng: gửi 1 tin gốc vào
  channel "Pancake Food Street" (workspace 4 / channel 11813), tag `@all` kèm
  link để mọi người vào đặt món.

  Token của admin tạo đợt (mỗi admin một token riêng — xem
  `FoodStreet.Settings.panchat_token/1`) được truyền vào khi gửi. Endpoint và
  payload tham chiếu theo Panchat MCP:

      POST https://pancakework.vn/api/workspaces/4/channels/11813/messages?token=<TOKEN>
      body: %{workspace_id, channel_id, channel_thread_id: nil, message,
              attachments, current_time (micro giây), key (uuid)}
  """

  require Logger

  alias FoodStreet.Ordering.GroupOrder

  @base_url "https://pancakework.vn"
  @workspace_id 4
  @channel_id 11_813

  @doc """
  Gửi lời mời ăn sáng cho 1 đợt đặt nhóm vào channel Panchat bằng `token` của
  admin tạo đợt.

  Trả `{:ok, message}` khi gửi thành công, `{:error, reason}` nếu thiếu token
  hoặc Panchat trả lỗi.
  """
  def send_breakfast_invite(%GroupOrder{} = group_order, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          send_channel_message(token, invite_text(group_order))
        end
    end
  end

  @doc "Nội dung tin mời ăn sáng (thuần, không gọi mạng — tách ra để dễ test)."
  def invite_text(%GroupOrder{} = go) do
    # Deep-link: mở thẳng đợt này để user chọn món ngay.
    link = "#{frontend_url()}/app?group=#{go.id}"

    note_line =
      case go.note do
        nil -> ""
        "" -> ""
        note -> "\n📝 #{note}"
      end

    """
    🍜 Đã mở đợt đặt đồ ăn: "#{go.title}" (📅 #{go.order_date})
    Mọi người vào đặt món nhé 👉 #{link}#{note_line}
    """
    |> String.trim_trailing()
  end

  @doc """
  Gửi 1 tin gốc bất kỳ vào channel Panchat cố định.

  Tách `build_body/1` ra để test thuần được payload mà không cần gọi mạng.
  """
  def send_channel_message(token, message) do
    url = "#{@base_url}/api/workspaces/#{@workspace_id}/channels/#{@channel_id}/messages"

    # `:panchat_req_options` cho phép test tiêm Req.Test plug thay vì gọi mạng thật.
    opts =
      [params: [token: token], json: build_body(message), receive_timeout: 10_000] ++
        Application.get_env(:food_street, :panchat_req_options, [])

    case Req.post(url, opts) do
      {:ok, %{body: %{"success" => true} = body}} ->
        {:ok, Map.get(body, "message")}

      {:ok, %{body: %{"success" => false} = body}} ->
        Logger.warning("Panchat gửi tin thất bại: #{inspect(body)}")
        {:error, {:panchat, Map.get(body, "message", "unknown")}}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Panchat trả về bất ngờ (#{status}): #{inspect(body)}")
        {:error, {:panchat, "http_#{status}"}}

      {:error, reason} ->
        Logger.warning("Panchat lỗi kết nối: #{inspect(reason)}")
        {:error, {:panchat, reason}}
    end
  end

  @doc """
  Dựng body gửi cho Panchat.
  """
  def build_body(message) do
    mention_all = %{
      "type" => "mention",
      "data" => [
        %{
          "type" => "all",
          "trigger" => "@",
          "name" => "all",
          "value" => @channel_id
        }
      ]
    }

    %{
      workspace_id: @workspace_id,
      channel_id: @channel_id,
      channel_thread_id: nil,
      message: message,
      attachments: [mention_all],
      current_time: System.os_time(:microsecond),
      key: Ecto.UUID.generate()
    }
  end

  defp frontend_url do
    Application.get_env(:food_street, :frontend_url, "http://localhost:5173")
  end
end
