defmodule FoodStreet.PancakeInbound do
  @moduledoc """
  Xử lý webhook `messaging` từ Pancake Page: khi **nhà bán trả lời**, dùng Gemini
  phân loại ý định tin rồi hành động phù hợp vào **Panchat nội bộ**:

  - `OUT_OF_STOCK` (hết món) → ping những người đã đặt đúng món đó vào đổi món.
  - `READY_FOR_PICKUP` (báo xuống lấy hàng) → ping nhóm đã bốc đi lấy đồ (runners).
  - `PAYMENT` (báo thanh toán) → relay nội dung + nhắc admin chuyển khoản (không ping ai).
  - `OTHER` / không có đợt mở / Gemini lỗi → relay nguyên văn như cũ. Riêng Gemini
    lỗi/timeout thì relay kèm 1 dòng báo phân loại lỗi.

  Vì webhook không gắn admin cụ thể, tin gửi bằng **token bot** (`Panchat.bot_token/0`,
  env `PANCHAT_BOT_TOKEN`). Chưa cấu hình `GEMINI_API_KEY` thì bỏ qua phân loại, relay
  thẳng như trước (không coi là lỗi).

  Được gọi async từ `PancakeWebhookController` (đã trả 200 cho Pancake trước đó).
  """

  require Logger

  alias FoodStreet.{Catalog, Panchat, Repo, Ordering, Gemini}
  alias FoodStreet.PancakeWebhookEvent

  @doc """
  Xử lý 1 payload webhook. Trả `{:ok, :relayed}` khi đã relay, `{:skip, reason}` khi bỏ
  qua hợp lệ (không phải tin nhà bán, không map được danh mục, tin trùng...),
  `{:error, reason}` khi lỗi thật (không có token admin, gửi Panchat lỗi).
  """
  def handle_messaging(payload) when is_map(payload) do
    with :ok <- ensure_messaging(payload),
         {:ok, ctx} <- extract(payload),
         :ok <- ensure_seller_reply(ctx),
         %Catalog.Category{} = category <-
           Catalog.get_category_by_conversation_id(ctx.conversation_id) || {:skip, :no_category},
         :ok <- ensure_not_processed(ctx.message_id),
         token when is_binary(token) <-
           Panchat.bot_token() || {:error, :no_bot_token} do
      # Chỉ đánh dấu đã xử lý SAU KHI gửi thành công — gửi lỗi (Panchat tạm chết)
      # thì để nguyên cho Pancake gửi lại (at-least-once: thà trùng còn hơn mất tin).
      case dispatch(category, ctx, token) do
        {:ok, :relayed} ->
          mark_processed(ctx.message_id)
          {:ok, :relayed}

        other ->
          other
      end
    else
      {:skip, _} = skip ->
        skip

      {:error, :no_bot_token} = err ->
        Logger.warning("[PancakeInbound] chưa cấu hình PANCHAT_BOT_TOKEN — bỏ xử lý")
        err

      {:error, _} = err ->
        err
    end
  end

  def handle_messaging(_), do: {:skip, :invalid_payload}

  # ---- các bước ----

  defp ensure_messaging(%{"event_type" => "messaging"}), do: :ok
  defp ensure_messaging(_), do: {:skip, :not_messaging}

  # Bóc các trường cần từ payload (JSON -> map key string).
  defp extract(payload) do
    conversation = get_in(payload, ["data", "conversation"]) || %{}
    message = get_in(payload, ["data", "message"]) || %{}

    ctx = %{
      page_id: payload["page_id"],
      conversation_id: conversation["id"],
      conversation_type: conversation["type"],
      message_id: message["id"],
      # Ưu tiên `original_message` (nội dung gốc nhà bán gõ); fallback `message`.
      text: message["original_message"] || message["message"],
      from_id: get_in(message, ["from", "id"]),
      from_name: get_in(message, ["from", "name"])
    }

    if is_binary(ctx.conversation_id) and is_binary(ctx.message_id) do
      {:ok, ctx}
    else
      {:skip, :missing_fields}
    end
  end

  # Chỉ relay tin INBOX, có nội dung, và TỪ NHÀ BÁN (from.id != page_id) — bỏ tin
  # outbound của chính ta để tránh loop.
  defp ensure_seller_reply(%{conversation_type: "INBOX"} = ctx) do
    cond do
      not (is_binary(ctx.text) and String.trim(ctx.text) != "") -> {:skip, :empty_text}
      ctx.from_id == ctx.page_id -> {:skip, :own_message}
      true -> :ok
    end
  end

  defp ensure_seller_reply(_), do: {:skip, :not_inbox}

  # Đã relay tin này chưa (theo message_id)?
  defp ensure_not_processed(message_id) do
    case Repo.get_by(PancakeWebhookEvent, message_id: message_id) do
      nil -> :ok
      _ -> {:skip, :duplicate}
    end
  end

  # Đánh dấu đã relay; đụng unique (redelivery đua nhau) thì bỏ qua im lặng.
  defp mark_processed(message_id) do
    %PancakeWebhookEvent{}
    |> PancakeWebhookEvent.changeset(%{message_id: message_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: :message_id)
  end

  # Phân loại tin nhà bán rồi hành động theo ý định. Đợt đang mở (nếu có) cần cho
  # OUT_OF_STOCK/READY_FOR_PICKUP; không có đợt mở thì mọi thứ về relay nguyên văn.
  defp dispatch(category, ctx, token) do
    go = Ordering.get_open_group_order_for_category(category.id)

    case classify_intent(category, ctx, go) do
      {:ok, %{intent: "OUT_OF_STOCK", items: items}} when not is_nil(go) ->
        case Ordering.users_ordering_items(go, items) do
          [] -> plain_relay(category, ctx, token)
          users -> normalize(Panchat.send_stock_alert(go, users, ctx.text, token))
        end

      {:ok, %{intent: "READY_FOR_PICKUP"}} when not is_nil(go) ->
        case Ordering.list_runners(go) do
          [] -> plain_relay(category, ctx, token)
          runners -> normalize(Panchat.send_runners_picked(go, runners, token))
        end

      {:ok, %{intent: "PAYMENT"}} ->
        normalize(
          Panchat.send_channel_message(token, payment_text(category, ctx), mention_all: false)
        )

      {:error, reason} ->
        Logger.warning("[PancakeInbound] Gemini phân loại lỗi: #{inspect(reason)}")
        plain_relay(category, ctx, token, gemini_failed: true)

      # OTHER, hoặc intent cần đợt mà không có đợt mở → relay nguyên văn.
      _ ->
        plain_relay(category, ctx, token)
    end
  end

  # Gọi Gemini nếu đã cấu hình key; chưa cấu hình thì coi như OTHER (relay cũ,
  # KHÔNG phải lỗi nên không gắn note).
  defp classify_intent(category, ctx, go) do
    if Gemini.enabled?() do
      Gemini.classify(ctx.text, %{
        category_name: category.name,
        item_names: Ordering.item_names_in_group(go)
      })
    else
      {:ok, %{intent: "OTHER", items: []}}
    end
  end

  # Relay nguyên văn (không tag @all). `gemini_failed: true` nối thêm 1 dòng báo lỗi.
  defp plain_relay(category, ctx, token, opts \\ []) do
    text = relay_text(category, ctx)

    text =
      if Keyword.get(opts, :gemini_failed, false) do
        text <> "\n⚙️ Gemini phân loại lỗi — gửi nguyên văn."
      else
        text
      end

    normalize(Panchat.send_channel_message(token, text, mention_all: false))
  end

  # Quy về {:ok, :relayed} khi gửi Panchat thành công; giữ nguyên {:error, _} để
  # KHÔNG mark_processed (Pancake sẽ gửi lại).
  defp normalize({:ok, _}), do: {:ok, :relayed}

  defp normalize({:error, reason} = err) do
    Logger.warning("[PancakeInbound] gửi Panchat lỗi: #{inspect(reason)}")
    err
  end

  @doc "Nội dung tin relay nguyên văn vào Panchat (thuần, không gọi mạng — tách để test)."
  def relay_text(%Catalog.Category{} = category, ctx) do
    """
    🛒 Nhà bán "#{category.name}" phản hồi:
    "#{String.trim(ctx.text)}"
    ⚠️ Có thể hết/đổi món — mọi người kiểm tra & đặt lại đơn nhé.
    """
    |> String.trim_trailing()
  end

  @doc "Nội dung tin báo nhà bán yêu cầu thanh toán (thuần, không gọi mạng)."
  def payment_text(%Catalog.Category{} = category, ctx) do
    """
    💳 Nhà bán "#{category.name}" báo thanh toán:
    "#{String.trim(ctx.text)}"
    🔔 Admin kiểm tra & chuyển khoản cho nhà bán nhé.
    """
    |> String.trim_trailing()
  end
end
