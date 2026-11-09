defmodule FoodStreet.Repo.Migrations.CreateSharedPageStates do
  use Ecto.Migration

  # Dữ liệu người xem nhập trên trang HTML chia sẻ (/share): 1 dòng / trang, dùng chung
  # cho mọi người. `data` là map key -> giá trị (ô input/select/... và localStorage giả).
  def change do
    create table(:shared_page_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Đường dẫn tương đối trong folder share/, vd "bao-cao/tuan-45.html"
      add :page_path, :string, null: false
      add :data, :map, null: false, default: %{}
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shared_page_states, [:page_path])
  end
end
