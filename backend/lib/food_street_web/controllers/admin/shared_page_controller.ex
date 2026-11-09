defmodule FoodStreetWeb.Admin.SharedPageController do
  @moduledoc """
  Admin quản lý trang HTML chia sẻ: duyệt thư mục, tạo thư mục, upload, xoá. Trang được
  serve (phải đăng nhập) ở `/share/<đường dẫn>` — xem `FoodStreetWeb.ShareController`.
  """
  use FoodStreetWeb, :controller

  alias FoodStreet.SharedPages

  action_fallback FoodStreetWeb.FallbackController

  # ?dir=a/b (trống = thư mục gốc)
  def index(conn, params) do
    with {:ok, listing} <- SharedPages.list(params["dir"]) do
      json(conn, %{data: listing})
    end
  end

  # multipart/form-data: `files[]` (nhiều file) hoặc `file`, `dir` (thư mục đích),
  # `overwrite` ("true" = ghi đè file trùng tên; mặc định báo lỗi đã tồn tại).
  # Lưu từng file độc lập: file lỗi không chặn các file hợp lệ còn lại.
  def create(conn, params) do
    uploads =
      (List.wrap(params["files"]) ++ List.wrap(params["file"]))
      |> Enum.filter(&match?(%Plug.Upload{}, &1))

    opts = [overwrite: params["overwrite"] in ["true", "1", true]]

    {saved, errors} =
      Enum.reduce(uploads, {[], []}, fn upload, {ok, err} ->
        case SharedPages.save(upload, params["dir"], opts) do
          {:ok, page} -> {[page | ok], err}
          {:error, reason} -> {ok, [%{name: upload.filename, error: message(reason)} | err]}
        end
      end)

    saved = Enum.reverse(saved)
    errors = Enum.reverse(errors)

    cond do
      uploads == [] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no_files", message: "Chưa chọn file nào để upload."})

      saved == [] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "upload_failed",
          message: Enum.map_join(errors, "; ", &"#{&1.name}: #{&1.error}"),
          errors: errors
        })

      true ->
        conn
        |> put_status(:created)
        |> json(%{data: saved, errors: errors})
    end
  end

  # {"dir": "a/b", "name": "Báo cáo Q4"}
  def create_folder(conn, params) do
    case SharedPages.create_folder(params["dir"], params["name"]) do
      {:ok, folder} ->
        conn |> put_status(:created) |> json(%{data: folder})

      {:error, reason} when reason in [:already_exists, :invalid_name] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason), message: message(reason)})

      error ->
        error
    end
  end

  # ?path=a/b/c.html (file) hoặc ?path=a/b (cả thư mục)
  def delete(conn, params) do
    with :ok <- SharedPages.delete(params["path"]) do
      send_resp(conn, :no_content, "")
    end
  end

  defp message(:invalid_extension),
    do: "Chỉ nhận file #{Enum.join(SharedPages.allowed_exts(), ", ")}."

  defp message(:file_too_large),
    do: "File vượt quá #{div(SharedPages.max_bytes(), 1024 * 1024)} MB."

  defp message(:empty_file), do: "File rỗng."
  defp message(:already_exists), do: "Đã tồn tại (tick \"Ghi đè\" để thay bản cũ)."
  defp message(:invalid_name), do: "Tên thư mục không hợp lệ."
  defp message(:not_found), do: "Thư mục không tồn tại."
  defp message(_), do: "Không ghi được lên server."
end
