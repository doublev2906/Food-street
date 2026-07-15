defmodule FoodStreet.Fund do
  @moduledoc """
  Quản lý quỹ đồ ăn sáng.

  Mỗi user có 1 số dư (`users.balance`). Admin nạp tiền (`deposit`) hoặc điều
  chỉnh (`adjust`). Mỗi thay đổi số dư được ghi lại 1 dòng `fund_transactions`
  để soi lịch sử. Việc trừ tiền khi chốt đơn nằm ở `FoodStreet.Ordering`.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Fund.FundTransaction
  alias FoodStreet.Fund.ExternalPurchase

  @doc "Lịch sử giao dịch quỹ của 1 user."
  def list_user_transactions(user_id) do
    FundTransaction
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @tx_types ~w(deposit order adjustment split)

  @doc """
  Toàn bộ giao dịch quỹ (admin) — phân trang + lọc.

  `params` (map string-key, đều tuỳ chọn): `"page"`, `"page_size"`, `"type"`
  (1 trong #{inspect(@tx_types)}), `"user_id"`, `"from"`/`"to"` (ISO date, lọc
  theo `inserted_at` quy về ngày VN UTC+7). Filter không hợp lệ bị bỏ qua.
  """
  def list_transactions(params \\ %{}) do
    page = params |> Map.get("page", 1) |> to_int(1) |> max(1)
    page_size = params |> Map.get("page_size", 20) |> to_int(20) |> min(100) |> max(1)

    query = filter_transactions(FundTransaction, params)
    total = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_by([t], desc: t.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:user, :created_by])
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      page_size: page_size,
      total: total,
      total_pages: max(ceil(total / page_size), 1)
    }
  end

  defp filter_transactions(query, params) do
    query
    |> filter_tx_type(params["type"])
    |> filter_tx_user(params["user_id"])
    |> filter_tx_from(params["from"])
    |> filter_tx_to(params["to"])
  end

  defp filter_tx_type(query, type) when type in @tx_types,
    do: where(query, [t], t.type == ^type)

  defp filter_tx_type(query, _), do: query

  defp filter_tx_user(query, user_id) when is_binary(user_id) and user_id != "" do
    case Ecto.UUID.cast(user_id) do
      {:ok, uid} -> where(query, [t], t.user_id == ^uid)
      :error -> query
    end
  end

  defp filter_tx_user(query, _), do: query

  defp filter_tx_from(query, date) do
    case parse_date(date) do
      {:ok, d} -> where(query, [t], t.inserted_at >= ^vn_day_start(d))
      :error -> query
    end
  end

  defp filter_tx_to(query, date) do
    case parse_date(date) do
      {:ok, d} -> where(query, [t], t.inserted_at < ^vn_day_start(Date.add(d, 1)))
      :error -> query
    end
  end

  # 00:00 giờ VN của `date` quy về UTC (= 00:00 UTC trừ 7 giờ).
  defp vn_day_start(date) do
    date
    |> NaiveDateTime.new!(~T[00:00:00])
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(-7 * 3600, :second)
  end

  defp parse_date(%Date{} = d), do: {:ok, d}

  defp parse_date(s) when is_binary(s) and s != "" do
    case Date.from_iso8601(s) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error

  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> default
    end
  end

  defp to_int(_, default), do: default

  @doc """
  Nạp tiền vào quỹ cho 1 user (`amount` > 0).

  Trừ hết **nợ lãi** (`interest_debt`, issue #12) trước, phần còn lại mới cộng vào
  số dư. Ví dụ nạp 100.000đ khi đang nợ lãi 272đ → 272đ gạt nợ lãi, 99.728đ vào
  số dư. Trả `{:ok, %{user, transaction, interest_paid}}`.
  """
  def deposit(%User{} = user, amount, %User{} = admin, description \\ nil) do
    with {:ok, decimal} <- to_decimal(amount) do
      interest_debt = user.interest_debt || Decimal.new(0)

      # Chỉ tiền nạp dương mới gạt nợ lãi; nạp âm (nếu có) coi như điều chỉnh thuần.
      pay_interest =
        if Decimal.compare(decimal, 0) == :gt,
          do: Decimal.min(decimal, interest_debt),
          else: Decimal.new(0)

      remainder = Decimal.sub(decimal, pay_interest)
      new_interest_debt = Decimal.sub(interest_debt, pay_interest)
      new_balance = Decimal.add(user.balance, remainder)

      Multi.new()
      |> Multi.update(:user, User.settle_changeset(user, new_balance, new_interest_debt))
      |> Multi.insert(:tx, fn _ ->
        FundTransaction.changeset(%FundTransaction{}, %{
          user_id: user.id,
          amount: remainder,
          type: "deposit",
          description: deposit_description(description, pay_interest),
          balance_after: new_balance,
          created_by_id: admin.id
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: updated, tx: tx}} ->
          {:ok, %{user: updated, transaction: tx, interest_paid: pay_interest}}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp deposit_description(description, pay_interest) do
    base = description || "Nạp quỹ"

    if Decimal.compare(pay_interest, 0) == :gt do
      "#{base} (đã trừ #{pay_interest}đ nợ lãi)"
    else
      base
    end
  end

  @doc """
  Điều chỉnh số dư: `amount` có thể âm hoặc dương. Dùng để sửa sai/hoàn tiền.
  """
  def adjust(%User{} = user, amount, %User{} = admin, description \\ nil) do
    apply_delta(user, amount, "adjustment", admin, description || "Điều chỉnh quỹ")
  end

  defp apply_delta(user, amount, type, admin, description) do
    with {:ok, decimal} <- to_decimal(amount) do
      new_balance = Decimal.add(user.balance, decimal)

      Multi.new()
      |> Multi.update(:user, User.balance_changeset(user, new_balance))
      |> Multi.insert(:tx, fn _ ->
        FundTransaction.changeset(%FundTransaction{}, %{
          user_id: user.id,
          amount: decimal,
          type: type,
          description: description,
          balance_after: new_balance,
          created_by_id: admin.id
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: updated, tx: tx}} -> {:ok, %{user: updated, transaction: tx}}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @doc "Tổng số dư toàn quỹ (cộng balance của mọi user)."
  def total_balance do
    Repo.aggregate(User, :sum, :balance) || Decimal.new(0)
  end

  @doc """
  Ghi nhận 1 khoản mua đồ ăn ngoài menu và chia tiền cho những người ăn.

  `attrs`: `%{"description", "total_amount", "purchase_date" (tuỳ chọn),
  "shares" => [%{"user_id", "amount"}]}`. Chỉ trừ số dư người ăn (không hoàn admin).
  Tổng các phần phải khớp đúng `total_amount`. Toàn bộ chạy trong 1 transaction.
  """
  def record_external_purchase(%User{} = admin, attrs) do
    description = attrs["description"] || attrs[:description]
    date = attrs["purchase_date"] || attrs[:purchase_date] || vn_today()
    raw_shares = attrs["shares"] || attrs[:shares] || []

    with {:ok, total} <- to_decimal(attrs["total_amount"] || attrs[:total_amount]),
         :ok <- ensure_positive(total),
         {:ok, shares} <- parse_shares(raw_shares),
         :ok <- ensure_sum_matches(shares, total),
         {:ok, users} <- load_users(shares) do
      run_external_purchase(admin, description, date, total, shares, users)
    end
  end

  @doc "Danh sách khoản mua ngoài (admin) — có phân trang."
  def list_external_purchases(page \\ 1, page_size \\ 20) do
    page = max(to_int(page, 1), 1)
    page_size = page_size |> to_int(20) |> min(100) |> max(1)
    total = Repo.aggregate(ExternalPurchase, :count, :id)

    entries =
      ExternalPurchase
      |> order_by([p], desc: p.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:created_by, transactions: :user])
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      page_size: page_size,
      total: total,
      total_pages: max(ceil(total / page_size), 1)
    }
  end

  defp run_external_purchase(admin, description, date, total, shares, users) do
    purchase_cs =
      ExternalPurchase.changeset(%ExternalPurchase{}, %{
        description: description,
        total_amount: total,
        purchase_date: date,
        created_by_id: admin.id
      })

    shares
    |> Enum.reduce(Multi.insert(Multi.new(), :purchase, purchase_cs), fn %{
                                                                           user_id: uid,
                                                                           amount: amt
                                                                         },
                                                                         m ->
      user = Map.fetch!(users, uid)
      new_balance = Decimal.sub(user.balance, amt)

      m
      |> Multi.update({:user, uid}, User.balance_changeset(user, new_balance))
      |> Multi.insert({:tx, uid}, fn %{purchase: p} ->
        FundTransaction.changeset(%FundTransaction{}, %{
          user_id: uid,
          amount: Decimal.negate(amt),
          type: "split",
          description: p.description,
          balance_after: new_balance,
          external_purchase_id: p.id,
          created_by_id: admin.id
        })
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{purchase: p}} ->
        {:ok, Repo.preload(p, [:created_by, transactions: :user], force: true)}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp ensure_positive(total) do
    if Decimal.compare(total, 0) == :gt, do: :ok, else: {:error, :invalid_amount}
  end

  defp parse_shares(raw) when is_list(raw) and raw != [] do
    raw
    |> Enum.reduce_while({:ok, []}, fn s, {:ok, acc} ->
      uid = s["user_id"] || s[:user_id]

      case to_decimal(s["amount"] || s[:amount]) do
        {:ok, amt} ->
          if is_binary(uid) and Decimal.compare(amt, 0) == :gt do
            {:cont, {:ok, [%{user_id: uid, amount: amt} | acc]}}
          else
            {:halt, {:error, :invalid_share}}
          end

        _ ->
          {:halt, {:error, :invalid_amount}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp parse_shares(_), do: {:error, :no_shares}

  defp ensure_sum_matches(shares, total) do
    sum = Enum.reduce(shares, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.amount) end)
    if Decimal.equal?(sum, total), do: :ok, else: {:error, :amount_mismatch}
  end

  defp load_users(shares) do
    ids = Enum.map(shares, & &1.user_id)
    uniq_ids = Enum.uniq(ids)

    cond do
      length(uniq_ids) != length(ids) ->
        {:error, :duplicate_user}

      true ->
        users = Repo.all(from u in User, where: u.id in ^uniq_ids)

        if length(users) == length(uniq_ids) do
          {:ok, Map.new(users, &{&1.id, &1})}
        else
          {:error, :user_not_found}
        end
    end
  end

  defp vn_today do
    DateTime.utc_now() |> DateTime.add(7 * 3600, :second) |> DateTime.to_date()
  end

  defp to_decimal(%Decimal{} = d), do: {:ok, d}
  defp to_decimal(n) when is_integer(n) or is_float(n), do: {:ok, Decimal.new(to_string(n))}

  defp to_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> {:ok, d}
      _ -> {:error, :invalid_amount}
    end
  end

  defp to_decimal(_), do: {:error, :invalid_amount}
end
