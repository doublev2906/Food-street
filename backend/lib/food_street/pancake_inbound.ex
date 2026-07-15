defmodule FoodStreet.PancakeInbound do
  @moduledoc """
  Xử lý webhook `messaging` từ Pancake Page: khi **nhà bán trả lời** (vd "hết món"),
  relay nguyên văn tin đó vào **Panchat nội bộ** để cả nhóm đổi/đặt lại đơn.

  Vì webhook không gắn admin cụ thể, tin relay được gửi bằng **token 1 admin ngẫu nhiên**
  (`Settings.random_admin_panchat_token/0`). `Panchat.send_channel_message/2` tự tag `@all`.

  Được gọi async từ `PancakeWebhookController` (đã trả 200 cho Pancake trước đó).
  """

  require Logger

  alias FoodStreet.{Catalog, Settings, Panchat, Repo}
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
         :ok <- ensure_not_processed(ctx.message_id) do
      # Chỉ đánh dấu đã xử lý SAU KHI relay thành công — relay lỗi (Panchat tạm chết)
      # thì để nguyên cho Pancake gửi lại (at-least-once: thà trùng còn hơn mất tin).
      case relay(category, ctx) do
        {:ok, :relayed} ->
          mark_processed(ctx.message_id)
          {:ok, :relayed}

        other ->
          other
      end
    else
      {:skip, _} = skip -> skip
      {:error, _} = err -> err
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
      text: message["message"],
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

  defp relay(category, ctx) do
    case Settings.random_admin_panchat_token() do
      nil ->
        Logger.warning("[PancakeInbound] không admin nào cấu hình Panchat token — bỏ relay")
        {:error, :no_admin_token}

      token ->
        case Panchat.send_channel_message(token, relay_text(category, ctx)) do
          {:ok, _} ->
            {:ok, :relayed}

          {:error, reason} = err ->
            Logger.warning("[PancakeInbound] relay Panchat lỗi: #{inspect(reason)}")
            err
        end
    end
  end

  @doc "Nội dung tin relay vào Panchat (thuần, không gọi mạng — tách để test)."
  def relay_text(%Catalog.Category{} = category, ctx) do
    """
    🛒 Nhà bán "#{category.name}" phản hồi:
    "#{String.trim(ctx.text)}"
    ⚠️ Có thể hết/đổi món — mọi người kiểm tra & đặt lại đơn nhé.
    """
    |> String.trim_trailing()
  end
end
