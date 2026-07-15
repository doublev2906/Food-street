defmodule FoodStreet.Interest do
  @moduledoc """
  Tính lãi (lãi kép, theo ngày) trên số dư âm của user và gom vào quỹ lãi riêng.

  Xem issue #12. Quy tắc:

    * Chỉ user có `balance < 0` (hoặc còn nợ lãi) mới bị tính lãi, dựa trên **dư nợ
      cuối ngày**.
    * Gốc tính lãi (lãi kép) = `|số dư âm| + nợ lãi hiện có` (`interest_debt`).
    * Lãi ngày = `max(gốc × lãi_suất_ngày, sàn)`, làm tròn **lên** đến đồng (VND
      là số nguyên, không có hào).
      - Lãi suất năm danh nghĩa mặc định **99%/năm** → ngày ≈ `99/36500 ≈ 0.2712%/ngày`.
      - Sàn tối thiểu mặc định **150đ/ngày** (âm là có lãi, không "lách" bằng âm ít).
    * Lãi **KHÔNG trừ vào balance** — cộng vào `users.interest_debt` (quỹ lãi riêng,
      tách khỏi tiền quỹ chung). Vì gốc tính lãi gồm cả `interest_debt` nên vẫn là
      **lãi kép** (nhập gốc). Khi user nạp tiền, tiền trừ hết `interest_debt` trước
      rồi phần còn lại mới vào `balance` (xem `FoodStreet.Fund.deposit/4`).
    * Mỗi lần tính lãi ghi 1 dòng `interest_charges` (sổ cái quỹ lãi) để đối soát &
      chia cổ tức sau này. Tổng quỹ đã cộng dồn = tổng `amount` bảng đó.

  Lãi suất & sàn để ở config (`config :food_street, #{inspect(__MODULE__)}`), không hardcode.

  `run_tick/1` được `FoodStreet.OrderScheduler` gọi định kỳ; idempotent trong ngày
  (VN) nhờ `job_runs` (key "interest_accrual") và unique (user_id, charged_on).
  Giờ tính theo giờ Việt Nam (UTC+7, không DST).
  """
  import Ecto.Query, warn: false
  require Logger

  alias Ecto.Multi
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Interest.InterestCharge
  alias FoodStreet.Scheduling

  @job "interest_accrual"
  @vn_offset_seconds 7 * 3600

  # Mặc định (ghi đè ở config): 99%/năm, sàn 150đ/ngày, chạy sau 02:00 giờ VN.
  @default_annual_rate_percent 99
  @default_min_daily_interest 150
  @default_accrual_hour 2

  # ------------------------------------------------------------------
  # Cấu hình
  # ------------------------------------------------------------------

  defp config, do: Application.get_env(:food_street, __MODULE__, [])

  @doc "Lãi suất năm danh nghĩa (%). Mặc định #{@default_annual_rate_percent}."
  def annual_rate_percent do
    Decimal.new(to_string(config()[:annual_rate_percent] || @default_annual_rate_percent))
  end

  @doc "Lãi sàn tối thiểu mỗi ngày (đồng). Mặc định #{@default_min_daily_interest}."
  def min_daily_interest do
    Decimal.new(to_string(config()[:min_daily_interest] || @default_min_daily_interest))
  end

  @doc "Giờ (VN) sớm nhất trong ngày được phép chạy tính lãi. Mặc định #{@default_accrual_hour}."
  def accrual_hour, do: config()[:accrual_hour] || @default_accrual_hour

  @doc "Lãi suất ngày (tỉ lệ thập phân) = `annual% / 100 / 365`."
  def daily_rate, do: Decimal.div(annual_rate_percent(), Decimal.new(36_500))

  @doc "Lãi suất ngày quy ra % (để hiển thị) = `annual% / 365`."
  def daily_rate_percent, do: Decimal.div(annual_rate_percent(), Decimal.new(365))

  # ------------------------------------------------------------------
  # Công thức lãi (thuần, không side-effect)
  # ------------------------------------------------------------------

  @doc """
  Gốc tính lãi của 1 user (lãi kép) = `|số dư âm| + nợ lãi`. Số dư ≥ 0 chỉ tính
  phần nợ lãi (thường là 0). Luôn ≥ 0.
  """
  def debt_base(%User{balance: balance, interest_debt: interest_debt}) do
    principal =
      if Decimal.compare(balance, 0) == :lt, do: Decimal.abs(balance), else: Decimal.new(0)

    Decimal.add(principal, interest_debt || Decimal.new(0))
  end

  @doc """
  Tiền lãi 1 ngày cho 1 gốc `base` (Decimal, ≥ 0).

  Trả `Decimal` số nguyên (đơn vị đồng, luôn làm tròn **LÊN**). Gốc ≤ 0 → 0. Gốc > 0
  → `max(ceil(base × lãi_suất_ngày), sàn)` (âm là có lãi → tối thiểu bằng sàn).
  """
  def compute_interest(%Decimal{} = base) do
    if Decimal.compare(base, 0) == :gt do
      by_percent =
        base
        |> Decimal.mult(daily_rate())
        |> Decimal.round(0, :ceiling)

      Decimal.max(by_percent, min_daily_interest())
    else
      Decimal.new(0)
    end
  end

  # ------------------------------------------------------------------
  # Job hằng ngày
  # ------------------------------------------------------------------

  @doc """
  Một nhịp chạy job tính lãi. Trả:
  - `{:ok, :accrued, %{count, total}}` khi đã tính lãi cho ngày hôm nay,
  - `{:ok, :skipped, :too_early}` khi chưa tới giờ `accrual_hour`,
  - `{:ok, :skipped, :already_done}` khi hôm nay đã chạy rồi.
  """
  def run_tick(now_utc \\ DateTime.utc_now()) do
    {vn_date, vn_time} = vn_now(now_utc)

    cond do
      vn_time.hour < accrual_hour() ->
        {:ok, :skipped, :too_early}

      Scheduling.job_ran_on(@job) == vn_date ->
        {:ok, :skipped, :already_done}

      true ->
        result = accrue_for_date(vn_date)
        Scheduling.mark_job_ran(@job, vn_date)

        Logger.info(
          "[Interest] Tính lãi #{vn_date}: #{result.count} người, tổng #{result.total}đ"
        )

        {:ok, :accrued, result}
    end
  end

  @doc """
  Chạy tính lãi cho ngày hôm nay NGAY (bỏ qua chặn giờ) — dùng cho nút bấm thủ công
  của admin. Vẫn idempotent trong ngày (không tính trùng người đã tính).
  """
  def accrue_today(now_utc \\ DateTime.utc_now()) do
    {vn_date, _} = vn_now(now_utc)
    result = accrue_for_date(vn_date)
    Scheduling.mark_job_ran(@job, vn_date)
    result
  end

  @doc """
  Tính lãi cho mọi user còn dư nợ (âm balance hoặc còn nợ lãi) chưa bị tính trong
  `vn_date`. Mỗi user chạy 1 transaction riêng để 1 người lỗi không kéo đổ cả mẻ.
  Trả `%{count, total}`.
  """
  def accrue_for_date(%Date{} = vn_date) do
    for user <- debtors_not_yet_charged(vn_date), reduce: %{count: 0, total: Decimal.new(0)} do
      acc ->
        case charge_user(user, vn_date) do
          {:ok, %{charge: charge}} ->
            %{count: acc.count + 1, total: Decimal.add(acc.total, charge.amount)}

          :skip ->
            acc

          {:error, step, reason, _} ->
            Logger.warning("[Interest] Bỏ qua #{user.id} (#{step}): #{inspect(reason)}")
            acc
        end
    end
  end

  defp debtors_not_yet_charged(vn_date) do
    already =
      Repo.all(from c in InterestCharge, where: c.charged_on == ^vn_date, select: c.user_id)

    query = from u in User, where: u.balance < 0 or u.interest_debt > 0

    query =
      if already == [], do: query, else: from(u in query, where: u.id not in ^already)

    Repo.all(query)
  end

  # 1 transaction: cộng lãi vào nợ lãi của user (KHÔNG đụng balance) + ghi sổ cái quỹ
  # lãi (interest_charges). unique (user_id, charged_on) chống tính trùng trong ngày.
  defp charge_user(%User{} = user, vn_date) do
    base = debt_base(user)
    interest = compute_interest(base)

    if Decimal.compare(interest, 0) == :gt do
      new_debt = Decimal.add(user.interest_debt || Decimal.new(0), interest)

      Multi.new()
      |> Multi.update(:user, User.interest_debt_changeset(user, new_debt))
      |> Multi.insert(:charge, fn _ ->
        InterestCharge.changeset(%InterestCharge{}, %{
          user_id: user.id,
          amount: interest,
          base_amount: base,
          interest_debt_after: new_debt,
          charged_on: vn_date
        })
      end)
      |> Repo.transaction()
    else
      :skip
    end
  end

  # ------------------------------------------------------------------
  # Báo cáo quỹ lãi
  # ------------------------------------------------------------------

  @doc """
  Tổng quan quỹ lãi:

    * `fund_total` — tổng lãi đã cộng dồn (accrual, tổng `interest_charges.amount`).
    * `outstanding_interest` — nợ lãi các user còn phải trả (tổng `users.interest_debt`).
    * `collected_total` — lãi đã thu thực (đã trả qua nạp tiền) = accrual − còn nợ.
    * `today_total` — lãi cộng dồn hôm nay.
    * `debtor_count`, `outstanding_debt` — số người & tổng dư nợ gốc đang âm.
    * `last_run_on` + thông số lãi suất để hiển thị.
  """
  def fund_summary(now_utc \\ DateTime.utc_now()) do
    {vn_date, _} = vn_now(now_utc)

    accrued = Repo.aggregate(InterestCharge, :sum, :amount) || Decimal.new(0)
    outstanding_interest = Repo.aggregate(User, :sum, :interest_debt) || Decimal.new(0)

    %{
      fund_total: accrued,
      collected_total: Decimal.sub(accrued, outstanding_interest),
      outstanding_interest: outstanding_interest,
      charge_count: Repo.aggregate(InterestCharge, :count, :id),
      today_total:
        Repo.one(from c in InterestCharge, where: c.charged_on == ^vn_date, select: sum(c.amount)) ||
          Decimal.new(0),
      debtor_count: Repo.aggregate(from(u in User, where: u.balance < 0), :count, :id),
      outstanding_debt:
        Repo.one(from u in User, where: u.balance < 0, select: sum(u.balance)) || Decimal.new(0),
      last_run_on: Scheduling.job_ran_on(@job),
      annual_rate_percent: annual_rate_percent(),
      daily_rate_percent: daily_rate_percent(),
      min_daily_interest: min_daily_interest()
    }
  end

  @doc """
  Tình trạng nợ của **1 user** (cho user tự xem):

    * `balance` — số dư hiện tại (âm = đang nợ gốc).
    * `interest_debt` — nợ lãi hiện có.
    * `principal_debt` — dư nợ gốc (`|số dư âm|`, 0 nếu số dư ≥ 0).
    * `total_owed` — tổng đang nợ = nợ gốc + nợ lãi.
    * `estimated_daily_interest` — lãi ước tính bị cộng cho ngày kế tiếp nếu vẫn nợ.
    * thông số lãi suất để hiển thị.
  """
  def user_status(%User{} = user) do
    interest_debt = user.interest_debt || Decimal.new(0)

    principal_debt =
      if Decimal.compare(user.balance, 0) == :lt,
        do: Decimal.abs(user.balance),
        else: Decimal.new(0)

    %{
      balance: user.balance,
      interest_debt: interest_debt,
      principal_debt: principal_debt,
      total_owed: Decimal.add(principal_debt, interest_debt),
      estimated_daily_interest: compute_interest(debt_base(user)),
      annual_rate_percent: annual_rate_percent(),
      daily_rate_percent: daily_rate_percent(),
      min_daily_interest: min_daily_interest()
    }
  end

  @doc """
  Lịch sử tính lãi (sổ cái quỹ) — phân trang, mới nhất trước. `params` (string-key,
  tuỳ chọn): `"page"`, `"page_size"`, `"user_id"`.
  """
  def list_charges(params \\ %{}) do
    page = params |> Map.get("page", 1) |> to_int(1) |> max(1)
    page_size = params |> Map.get("page_size", 20) |> to_int(20) |> min(100) |> max(1)

    query = filter_user(InterestCharge, params["user_id"])
    total = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_by([c], desc: c.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:user)
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      page_size: page_size,
      total: total,
      total_pages: max(ceil(total / page_size), 1)
    }
  end

  defp filter_user(query, user_id) when is_binary(user_id) and user_id != "" do
    case Ecto.UUID.cast(user_id) do
      {:ok, uid} -> where(query, [c], c.user_id == ^uid)
      :error -> query
    end
  end

  defp filter_user(query, _), do: query

  # ------------------------------------------------------------------
  # Tiện ích
  # ------------------------------------------------------------------

  defp vn_now(now_utc) do
    vn = DateTime.add(now_utc, @vn_offset_seconds, :second)
    {DateTime.to_date(vn), DateTime.to_time(vn)}
  end

  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> default
    end
  end

  defp to_int(_, default), do: default
end
