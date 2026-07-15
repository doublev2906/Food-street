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

  alias FoodStreet.Accounts
  alias FoodStreet.Ordering.GroupOrder
  alias FoodStreet.Fund.ExternalPurchase

  @base_url "https://pancakework.vn"
  @workspace_id 4
  @channel_id 11_813

  # URL trong nội dung tin (http/https, tới khoảng trắng đầu tiên).
  @url_regex ~r{https?://\S+}

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
  Gửi tin báo những người được bốc đi lấy đồ cho 1 đợt, bằng `token` của admin
  thực hiện. `users` là danh sách `%User{}` (có `name`, `panchat_user_id`).

  Chỉ mention thật (ping) người có `panchat_user_id`; người chưa có UUID vẫn hiển
  thị `@Tên` dạng text thường. Trả `{:ok, message}` hoặc `{:error, reason}`.
  """
  def send_runners_picked(%GroupOrder{} = go, users, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          post_message(token, runners_body(go, users))
        end
    end
  end

  @doc """
  Test nhanh việc gửi thông báo Panchat: lấy TẤT CẢ user trong DB có
  `panchat_user_id` rồi gửi 1 tin mention thử vào channel — KHÔNG cần tạo đợt/đơn.

  ⚠️ Gửi thật vào channel Pancake Food Street (workspace #{@workspace_id} /
  channel #{@channel_id}), nên tiêu đề đánh dấu "[TEST]" cho mọi người biết.

  Cần token Panchat của 1 admin (mỗi admin 1 token — xem `FoodStreet.Settings`).
  Chạy trong IEx trên server:

      iex> token = FoodStreet.Settings.panchat_token("<admin_id>")
      iex> FoodStreet.Panchat.test_notify_panchat_users(token)

  Trả `{:ok, message}` khi Panchat nhận; `{:error, :panchat_token_missing}` nếu
  thiếu token; `{:error, :no_panchat_users}` nếu chưa user nào có `panchat_user_id`.
  """
  def test_notify_panchat_users(token) do
    case Accounts.list_users_with_panchat_id() do
      [] ->
        {:error, :no_panchat_users}

      users ->
        go = %GroupOrder{title: "[TEST] báo Panchat", order_date: Date.utc_today()}
        send_runners_picked(go, users, token)
    end
  end

  @doc """
  Body tin báo người đi lấy đồ: 1 paragraph tiêu đề, 1 paragraph liệt kê người
  được chọn (mention thật ai có `panchat_user_id`) và 1 paragraph nhắc nhở.
  Tách ra để test thuần payload, không gọi mạng.
  """
  def runners_body(%GroupOrder{} = go, users) do
    header = %{
      "type" => "paragraph",
      "content" => "🎲 Người đi lấy đồ đợt \"#{go.title}\" (📅 #{go.order_date})"
    }

    footer = %{"type" => "paragraph", "content" => "Nhớ đi lấy hàng giúp cả nhà nhé 🙏"}

    %{"text" => [header, runners_paragraph(users), footer]}
  end

  # Paragraph "👉 @A @B @C" với mention span (offset UTF-16) cho người có UUID Panchat.
  defp runners_paragraph(users) do
    prefix = "👉 "

    {content, spans, _offset} =
      users
      |> Enum.with_index()
      |> Enum.reduce({prefix, [], utf16_length(prefix)}, fn {user, idx},
                                                            {content, spans, offset} ->
        sep = if idx == 0, do: "", else: " "
        offset = offset + utf16_length(sep)
        mention = "@#{user.name}"
        m_len = utf16_length(mention)

        new_spans =
          if valid_panchat_id?(user.panchat_user_id) do
            spans ++ [mention_span(offset, offset + m_len, user.panchat_user_id)]
          else
            spans
          end

        {content <> sep <> mention, new_spans, offset + m_len}
      end)

    %{"type" => "paragraph", "content" => content, "spans" => spans}
  end

  defp mention_span(from, to, user_id) do
    %{
      "type" => "mention",
      "from" => from,
      "to" => to,
      "ref" => %{"type" => "user", "user_id" => user_id}
    }
  end

  defp valid_panchat_id?(pid), do: is_binary(pid) and pid != ""

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
  `users` là danh sách `%User{}` (có `name`, `balance`, `panchat_user_id`).

  Ai nợ quá 50k (balance < -50.000) và đã có `panchat_user_id` sẽ được mention thật
  (@Tên, ping) kèm lời nhắc — xem `balance_report_body/2`.
  """
  def send_balance_report(users, date, token) do
    case token do
      nil ->
        {:error, :panchat_token_missing}

      token ->
        if String.trim(token) == "" do
          {:error, :panchat_token_missing}
        else
          post_message(token, balance_report_body(users, date))
        end
    end
  end

  # Ngưỡng cảnh báo: nợ quá 50k (balance âm hơn -50.000).
  @warn_threshold Decimal.new("-50000")
  @warn_message "Không donate sớm thì nhịn nhé"

  @doc """
  Body tin báo số dư: phần text chung (qua `build_body/1`, có @all + link span) rồi
  nối thêm mỗi con nợ nặng 1 paragraph mention thật `@Tên #{@warn_message}`.

  Chỉ mention người có `panchat_user_id` (UUID Panchat) — không có thì bỏ qua để
  tránh gửi span rỗng/hỏng.
  """
  def balance_report_body(users, date) do
    users
    |> balance_report_text(date)
    |> build_body()
    |> Map.update!("text", &(&1 ++ debtor_paragraphs(users)))
  end

  defp debtor_paragraphs(users) do
    users
    |> Enum.filter(&debtor?/1)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&debtor_paragraph/1)
  end

  # Nợ nặng = có UUID Panchat và balance < -50.000.
  defp debtor?(%{balance: balance, panchat_user_id: pid})
       when is_binary(pid) and pid != "" and not is_nil(balance) do
    Decimal.compare(balance, @warn_threshold) == :lt
  end

  defp debtor?(_), do: false

  defp debtor_paragraph(user) do
    mention = "@#{user.name}"

    %{
      "type" => "paragraph",
      "content" => "#{mention} #{@warn_message}",
      "spans" => [
        %{
          "type" => "mention",
          "from" => 0,
          "to" => utf16_length(mention),
          "ref" => %{"type" => "user", "user_id" => user.panchat_user_id}
        }
      ]
    }
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
    post_message(token, build_body(message))
  end

  # POST body `SendMessageRequest` đã dựng sẵn vào channel cố định.
  defp post_message(token, body) do
    url = "#{@base_url}/api/v2/channels/#{@channel_id}/messages"

    # `:panchat_req_options` cho phép test tiêm Req.Test plug thay vì gọi mạng thật.
    opts =
      [
        params: [workspace_id: @workspace_id],
        auth: {:bearer, token},
        json: body,
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
  Dựng body `SendMessageRequest` cho Pancake Work API v2 (chỉ khoá `text`).

  Nội dung là RichText — danh sách paragraph node. Mỗi dòng của `message` thành 1
  paragraph; @all được gắn bằng 1 `mention` span (ref `all`) ở đầu paragraph thứ
  nhất, offset 0..4 ứng với đúng chữ "@all".

  Mọi URL http/https trong nội dung được gắn thêm 1 `link` span để hiển thị link
  bấm được. `link_previews` KHÔNG gửi ở request — server tự trích từ URL trong
  tin (xem schema `StandardMessagePayload`).

  `from`/`to` của span là offset theo đơn vị UTF-16 code unit — đúng như editor
  Panchat (JS) sinh ra: ký tự BMP tính 1, emoji ngoài BMP như 📅/👉 tính 2. (Doc
  OpenAPI ghi "grapheme offset" nhưng client thực tế dùng UTF-16, vd link ở
  offset 71 chứ không phải 69 khi có 2 emoji đứng trước.)
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

    %{"text" => [first_paragraph | Enum.map(rest, &paragraph/1)]}
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

  defp frontend_url do
    Application.get_env(:food_street, :frontend_url, "http://localhost:5173")
  end
end
