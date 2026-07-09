defmodule FoodStreet.Panchat do
  @moduledoc """
  Gửi tin nhắn vào Panchat (pancakework.vn).

  Dùng để báo cho cả nhóm khi admin mở 1 đợt đặt đồ ăn sáng: gửi 1 tin gốc vào
  channel "Pancake Food Street" (workspace 4 / channel 11813), tag `@all` kèm
  link để mọi người vào đặt món.

  Token của admin tạo đợt (mỗi admin một token riêng — xem
  `FoodStreet.Settings.panchat_token/1`) được gửi qua header Bearer. Endpoint và
  payload theo Pancake Work API v2 (operation `sendChannelMessage`):

      POST https://pancakework.vn/api/v2/channels/11813/messages?workspace_id=4
      Authorization: Bearer <TOKEN>
      body: %{text: [%{type: "paragraph", content: ..., spans: [mention @all]}]}
  """

  require Logger

  alias FoodStreet.Ordering.GroupOrder
  alias FoodStreet.Fund.ExternalPurchase

  @base_url "https://pancakework.vn"
  @workspace_id 4
  @channel_id 11_813

  # URL trong nội dung tin (http/https, tới khoảng trắng đầu tiên).
  @url_regex ~r{https?://\S+}
  # Tiêu đề preview cho link app (SPA nên OG title cố định cho mọi đợt).
  @app_link_title "Food Street · Đặt đồ ăn sáng"

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
  Gửi tin tổng kết (gọn) khi admin chốt cả đợt, bằng `token` của admin bấm chốt.
  """
  def send_group_closed_summary(%GroupOrder{} = go, count, total, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          send_channel_message(token, close_text(go, count, total))
        end
    end
  end

  @doc "Gửi tin báo huỷ/xoá đợt, bằng `token` của admin thực hiện."
  def send_group_deleted(%GroupOrder{} = go, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          send_channel_message(token, deleted_text(go))
        end
    end
  end

  @doc """
  Gửi tin chia tiền mua ngoài (tag @all qua `build_body/1`), bằng `token` của
  admin thực hiện. `purchase` cần preload `transactions: :user`.
  """
  def send_external_purchase(%ExternalPurchase{} = purchase, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          send_channel_message(token, external_purchase_text(purchase))
        end
    end
  end

  @doc """
  Gửi tin báo số dư từng người (tag @all qua `build_body/1`), bằng `token` truyền vào.
  `users` là danh sách `%User{}` (có `name`, `balance`).
  """
  def send_balance_report(users, date, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          send_channel_message(token, balance_report_text(users, date))
        end
    end
  end

  @doc "Nội dung tin báo số dư quỹ (thuần, không gọi mạng)."
  def balance_report_text(users, date) do
    lines =
      users
      |> Enum.sort_by(& &1.name)
      |> Enum.map_join("\n", fn u -> "• #{u.name}: #{format_vnd(u.balance)}" end)

    """
    💰 Số dư quỹ ăn sáng (📅 #{date}):
    #{lines}
    Ace âm tiền nhớ donate quỹ để tránh gián đoạn việc ăn uống nhé
    """
    |> String.trim_trailing()
  end

  @doc "Nội dung tin chia tiền mua ngoài (thuần, không gọi mạng)."
  def external_purchase_text(%ExternalPurchase{} = p) do
    lines =
      (p.transactions || [])
      |> Enum.map_join("\n", fn tx ->
        name = (tx.user && tx.user.name) || "?"
        "• #{name}: #{format_vnd(Decimal.abs(tx.amount))}"
      end)

    """
    💸 Chia tiền mua ngoài: "#{p.description}" (📅 #{p.purchase_date})
    Tổng #{format_vnd(p.total_amount)} — mỗi người:
    #{lines}
    """
    |> String.trim_trailing()
  end

  @doc "Nội dung tin báo xoá đợt (thuần, không gọi mạng)."
  def deleted_text(%GroupOrder{} = go) do
    """
    ❌ Đã huỷ đợt đặt: "#{go.title}" (📅 #{go.order_date})
    """
    |> String.trim_trailing()
  end

  @doc "Nội dung tin tổng kết khi chốt đợt (thuần, không gọi mạng)."
  def close_text(%GroupOrder{} = go, count, total) do
    link = "#{frontend_url()}/app?group=#{go.id}"

    """
    ✅ Đã chốt đợt: "#{go.title}" (📅 #{go.order_date})
    #{count} đơn · tổng #{format_vnd(total)} 👉 #{link}
    """
    |> String.trim_trailing()
  end

  # Định dạng tiền kiểu VN (vd 90000 -> "90.000đ"), nhận Decimal/số/nil.
  defp format_vnd(nil), do: "0đ"

  defp format_vnd(amount) do
    int =
      amount
      |> to_string()
      |> String.split(".")
      |> hd()

    grouped =
      int
      |> String.replace_leading("-", "")
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()
      |> Enum.map(&Enum.join/1)
      |> Enum.join(".")

    sign = if String.starts_with?(int, "-"), do: "-", else: ""
    "#{sign}#{grouped}đ"
  end

  @doc """
  Gửi 1 tin gốc bất kỳ vào channel Panchat cố định (Pancake Work API v2).

      POST #{@base_url}/api/v2/channels/{channel_id}/messages?workspace_id={ws}
      Authorization: Bearer <token>

  `token` là JWT của admin (xem `FoodStreet.Settings.panchat_token/1`), gửi qua
  header Bearer. Thành công khi HTTP 2xx (200 trả về message vừa tạo, 204 khi là
  lệnh không tạo tin). Tách `build_body/1` ra để test thuần payload không gọi mạng.
  """
  def send_channel_message(token, message) do
    url = "#{@base_url}/api/v2/channels/#{@channel_id}/messages"

    # `:panchat_req_options` cho phép test tiêm Req.Test plug thay vì gọi mạng thật.
    opts =
      [
        params: [workspace_id: @workspace_id],
        auth: {:bearer, token},
        json: build_body(message),
        receive_timeout: 10_000
      ] ++ Application.get_env(:food_street, :panchat_req_options, [])

    case Req.post(url, opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Panchat trả về bất ngờ (#{status}): #{inspect(body)}")
        {:error, {:panchat, "http_#{status}"}}

      {:error, reason} ->
        Logger.warning("Panchat lỗi kết nối: #{inspect(reason)}")
        {:error, {:panchat, reason}}
    end
  end

  @doc """
  Dựng body `SendMessageRequest` cho Pancake Work API v2.

  Nội dung là RichText — danh sách paragraph node. Mỗi dòng của `message` thành 1
  paragraph; @all được gắn bằng 1 `mention` span (ref `all`) ở đầu paragraph thứ
  nhất, offset 0..4 ứng với đúng chữ "@all".

  Mọi URL http/https trong nội dung được gắn thêm `link` span để hiển thị link
  bấm được, kèm 1 `link_previews` cho mỗi URL. `from`/`to` của span là offset
  theo đơn vị UTF-16 code unit (giống `String.length` của JS mà editor Panchat
  dùng): ký tự BMP tính 1, emoji ngoài BMP như 📅/👉 tính 2.
  """
  def build_body(message) do
    [first | rest] = String.split(message, "\n")

    first_content = "@all " <> first

    mention_span = %{
      "type" => "mention",
      "from" => 0,
      "to" => 4,
      "ref" => %{"type" => "all", "channel_id" => @channel_id}
    }

    first_paragraph = %{
      "type" => "paragraph",
      "content" => first_content,
      "spans" => [mention_span | link_spans(first_content)]
    }

    rest_paragraphs = Enum.map(rest, &paragraph/1)

    urls =
      message
      |> url_matches()
      |> Enum.map(fn {url, _offset} -> url end)
      |> Enum.uniq()

    %{
      "type" => "v1/standard",
      "text" => [first_paragraph | rest_paragraphs],
      "attachments" => [],
      "link_previews" => Enum.map(urls, &link_preview/1)
    }
  end

  # 1 dòng -> paragraph node; chỉ thêm khoá "spans" khi có link để giữ payload gọn.
  defp paragraph(line) do
    base = %{"type" => "paragraph", "content" => line}

    case link_spans(line) do
      [] -> base
      spans -> Map.put(base, "spans", spans)
    end
  end

  # Các `link` span cho mọi URL trong `content` (offset theo UTF-16 code unit).
  defp link_spans(content) do
    Enum.map(url_matches(content), fn {url, byte_offset} ->
      from = content |> binary_part(0, byte_offset) |> utf16_length()

      %{
        "type" => "link",
        "from" => from,
        "to" => from + utf16_length(url),
        "url" => url
      }
    end)
  end

  # Danh sách {url, byte_offset} của mọi URL trong `content` (byte_offset để cắt chuỗi).
  defp url_matches(content) do
    @url_regex
    |> Regex.scan(content, return: :index)
    |> Enum.map(fn [{start, len}] -> {binary_part(content, start, len), start} end)
  end

  # Độ dài chuỗi theo UTF-16 code unit: codepoint ngoài BMP (emoji) tính 2 đơn vị.
  defp utf16_length(string) do
    string
    |> String.to_charlist()
    |> Enum.reduce(0, fn cp, acc -> acc + if(cp > 0xFFFF, do: 2, else: 1) end)
  end

  defp link_preview(url) do
    %{
      "url" => url,
      "title" => @app_link_title,
      "icon" => "#{frontend_url()}/favicon.svg"
    }
  end

  defp frontend_url do
    Application.get_env(:food_street, :frontend_url, "http://localhost:5173")
  end
end
