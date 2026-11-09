defmodule FoodStreetWeb.Admin.SharedPageController do
  @moduledoc """
  Admin upload / xoá trang HTML chia sẻ. File được Caddy serve (phải đăng nhập) ở
  `/share/<tên file>` — xem `FoodStreet.SharedPages`.
  """
  use FoodStreetWeb, :controller

  alias FoodStreet.SharedPages

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: SharedPages.list()})
  end

  # multipart/form-data, field `files[]` (nhiều file) hoặc `file` (1 file).
  # Lưu từng file độc lập: file lỗi không chặn các file hợp lệ còn lại.
  def create(conn, params) do
    uploads =
      (List.wrap(params["files"]) ++ List.wrap(params["file"]))
      |> Enum.filter(&match?(%Plug.Upload{}, &1))

    {saved, errors} =
      Enum.reduce(uploads, {[], []}, fn upload, {ok, err} ->
        case SharedPages.save(upload) do
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

  def delete(conn, %{"name" => name}) do
    with :ok <- SharedPages.delete(name) do
      send_resp(conn, :no_content, "")
    end
  end

  defp message(:invalid_extension),
    do: "Chỉ nhận file #{Enum.join(SharedPages.allowed_exts(), ", ")}."

  defp message(:file_too_large),
    do: "File vượt quá #{div(SharedPages.max_bytes(), 1024 * 1024)} MB."

  defp message(:empty_file), do: "File rỗng."
  defp message(_), do: "Không ghi được file lên server."
end
