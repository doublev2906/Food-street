defmodule FoodStreet.Ordering.GroupOrder do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Accounts.User
  alias FoodStreet.Catalog.Category
  alias FoodStreet.Ordering.Order

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :title,
             :order_date,
             :status,
             :note,
             :deadline,
             :closed_at,
             :seller_paid_at,
             :runner_count,
             :category_id,
             :created_by_id,
             :inserted_at
           ]}

  @statuses ~w(open closed cancelled)

  schema "group_orders" do
    field :title, :string
    field :order_date, :date
    field :status, :string, default: "open"
    field :note, :string
    field :deadline, :utc_datetime
    field :closed_at, :utc_datetime

    # Thời điểm admin tick tay "đã thanh toán cho người bán" — null = chưa trả (issue #10).
    # Không cast trong changeset thường; chỉ set qua seller_paid_changeset/2.
    field :seller_paid_at, :utc_datetime
    field :runner_count, :integer, default: 0

    belongs_to :category, Category
    belongs_to :created_by, User
    has_many :orders, Order

    timestamps(type: :utc_datetime)
  end

  def changeset(group_order, attrs) do
    group_order
    |> cast(attrs, [
      :title,
      :order_date,
      :status,
      :note,
      :deadline,
      :runner_count,
      :category_id,
      :created_by_id
    ])
    |> validate_required([:title, :order_date, :category_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:runner_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:category_id)
  end

  def status_changeset(group_order, attrs) do
    group_order
    |> cast(attrs, [:status, :closed_at])
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Tick/bỏ tick đã thanh toán người bán (`at` = thời điểm tick, nil = bỏ tick)."
  def seller_paid_changeset(group_order, at) do
    change(group_order, seller_paid_at: at)
  end
end
