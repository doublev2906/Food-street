defmodule FoodStreet.SharedPages do
  @moduledoc """
  Trang HTML chia sẻ: file nằm trong folder `share/` (root repo) và được Caddy
  serve (phải đăng nhập) ở `/share/<tên file>` (kèm trang danh sách `/share/`).

  Có 2 đường đưa file lên server:
    * Admin upload qua UI (module này ghi file vào `share_dir`).
    * `make share` dưới máy dev (rsync thẳng folder `share/` lên server).

  Folder đích cấu hình qua `config :food_street, :share_dir` (prod: env `SHARE_DIR`).
  """

  @allowed_exts ~w(.html .htm)
  @max_bytes 20 * 1024 * 1024
  @max_stem_length 100

  @type page :: %{
          name: String.t(),
          size: non_neg_integer(),
          updated_at: String.t(),
          url: String.t()
        }

  def max_bytes, do: @max_bytes
  def allowed_exts, do: @allowed_exts

  def dir, do: Application.fetch_env!(:food_street, :share_dir)

  @doc "Danh sách file đang chia sẻ (bỏ file ẩn và thư mục con), mới sửa trước."
  @spec list() :: [page()]
  def list do
    case File.ls(dir()) do
      {:ok, names} ->
        names
        |> Enum.reject(&hidden?/1)
        |> Enum.flat_map(fn name ->
          case info(name) do
            {:ok, page} -> [page]
            :error -> []
          end
        end)
        |> Enum.sort_by(& &1.updated_at, :desc)

      {:error, _} ->
        []
    end
  end

  @doc """
  Lưu 1 file upload vào folder chia sẻ. Tên file được chuẩn hoá (bỏ dấu, chữ
  thường, chỉ giữ `a-z0-9._-`); trùng tên thì ghi đè.
  """
  @spec save(Plug.Upload.t()) :: {:ok, map()} | {:error, atom()}
  def save(%Plug.Upload{path: tmp_path, filename: filename}) do
    with {:ok, name} <- sanitize_name(filename),
         {:ok, %File.Stat{size: size}} <- File.stat(tmp_path),
         :ok <- check_size(size),
         :ok <- File.mkdir_p(dir()) do
      dest = Path.join(dir(), name)
      replaced? = File.exists?(dest)
      # Ghi ra file tạm (ẩn) rồi rename để Caddy không bao giờ serve file ghi dở.
      tmp_dest = Path.join(dir(), ".upload-#{System.unique_integer([:positive])}-#{name}")

      with :ok <- File.cp(tmp_path, tmp_dest),
           :ok <- File.chmod(tmp_dest, 0o644),
           :ok <- File.rename(tmp_dest, dest),
           {:ok, page} <- info(name) do
        {:ok, Map.put(page, :replaced, replaced?)}
      else
        _ ->
          File.rm(tmp_dest)
          {:error, :write_failed}
      end
    end
  end

  @doc "Xoá 1 file đang chia sẻ (chỉ file nằm trực tiếp trong folder, không xoá thư mục)."
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(name) when is_binary(name) do
    with true <- plain_name?(name),
         path = Path.join(dir(), name),
         {:ok, %File.Stat{type: :regular}} <- File.stat(path),
         :ok <- File.rm(path) do
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Chuẩn hoá tên file upload thành tên an toàn cho URL.

      iex> FoodStreet.SharedPages.sanitize_name("Báo cáo tháng 11.HTML")
      {:ok, "bao-cao-thang-11.html"}
  """
  @spec sanitize_name(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_extension}
  def sanitize_name(filename) when is_binary(filename) do
    # Trình duyệt cũ có thể gửi kèm đường dẫn Windows (C:\fakepath\a.html).
    base = filename |> String.replace("\\", "/") |> Path.basename()
    ext = base |> Path.extname() |> String.downcase()

    if ext in @allowed_exts do
      stem =
        base
        |> Path.rootname()
        |> slugify()
        |> String.slice(0, @max_stem_length)
        |> String.trim_trailing("-")

      {:ok, if(stem == "", do: "page", else: stem) <> ext}
    else
      {:error, :invalid_extension}
    end
  end

  def sanitize_name(_), do: {:error, :invalid_extension}

  defp slugify(str) do
    str
    |> String.replace(["đ", "Đ"], "d")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]+/, "-")
    |> String.replace(~r/-{2,}/, "-")
    # Bỏ dấu chấm/gạch ở đầu-cuối: tránh tạo file ẩn (.abc) hoặc tên xấu.
    |> String.replace(~r/^[.-]+|[.-]+$/, "")
  end

  defp check_size(0), do: {:error, :empty_file}
  defp check_size(size) when size > @max_bytes, do: {:error, :file_too_large}
  defp check_size(_), do: :ok

  defp info(name) do
    case File.stat(Path.join(dir(), name), time: :posix) do
      {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} ->
        {:ok,
         %{
           name: name,
           size: size,
           updated_at: mtime |> DateTime.from_unix!() |> DateTime.to_iso8601(),
           url: "/share/" <> URI.encode(name, &URI.char_unreserved?/1)
         }}

      _ ->
        :error
    end
  end

  defp hidden?(name), do: String.starts_with?(name, ".")

  # Tên file "trần": không rỗng, không ẩn, không chứa dấu phân cách đường dẫn.
  defp plain_name?(name) do
    name != "" and not hidden?(name) and Path.basename(name) == name and
      not String.contains?(name, ["/", "\\", <<0>>])
  end
end
