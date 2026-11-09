defmodule FoodStreetWeb.ShareListing do
  @moduledoc "Trang danh sách thư mục `/share/...` (HTML tĩnh, không script)."

  alias FoodStreet.SharedPages

  @vn_offset_seconds 7 * 3600

  def render(%{dir: dir, folders: folders, files: files}) do
    rows =
      if folders == [] and files == [] do
        ~s(<tr><td colspan="3" class="muted">Thư mục trống.</td></tr>)
      else
        Enum.map(folders, &row(&1, "📁")) ++ Enum.map(files, &row(&1, "📄"))
      end

    [
      """
      <!doctype html>
      <html lang="vi"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>#{esc(title(dir))} · Food Street</title>
      <style>
        body{font:14px/1.5 system-ui,-apple-system,sans-serif;margin:0;background:#f4f5f7;color:#1f2937}
        main{max-width:960px;margin:32px auto;padding:0 16px}
        h1{font-size:18px;margin:0 0 16px}
        nav a{color:#2563eb;text-decoration:none} nav a:hover{text-decoration:underline}
        table{width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;
          box-shadow:0 1px 3px rgba(0,0,0,.08)}
        td,th{padding:10px 14px;border-bottom:1px solid #eef0f3;text-align:left}
        th{font-size:12px;text-transform:uppercase;color:#6b7280;letter-spacing:.04em}
        td a{color:#111827;text-decoration:none;font-weight:500} td a:hover{color:#2563eb}
        .muted{color:#6b7280}.num{white-space:nowrap;color:#6b7280}
      </style></head><body><main>
      <h1>🔗 Trang chia sẻ</h1>
      <nav>#{breadcrumb(dir)}</nav><br>
      <table><thead><tr><th>Tên</th><th>Dung lượng</th><th>Cập nhật</th></tr></thead><tbody>
      """,
      rows,
      "</tbody></table></main></body></html>"
    ]
  end

  defp row(entry, icon) do
    size = if entry.type == :folder, do: "—", else: format_bytes(entry.size)

    ~s(<tr><td>#{icon} <a href="#{esc(entry.url)}">#{esc(entry.name)}#{if entry.type == :folder, do: "/"}</a></td>) <>
      ~s(<td class="num">#{size}</td><td class="num">#{format_time(entry.updated_at)}</td></tr>)
  end

  defp title(""), do: "share"
  defp title(dir), do: "share/" <> dir

  defp breadcrumb(dir) do
    segments = String.split(dir, "/", trim: true)

    crumbs =
      segments
      |> Enum.with_index(1)
      |> Enum.map(fn {seg, i} ->
        path = segments |> Enum.take(i) |> Enum.join("/")
        ~s( / <a href="#{esc(SharedPages.url_for(path, :folder))}">#{esc(seg)}</a>)
      end)

    ~s(<a href="/share/">share</a>) <> Enum.join(crumbs)
  end

  defp format_bytes(n) when n < 1024, do: "#{n} B"
  defp format_bytes(n) when n < 1024 * 1024, do: "#{Float.round(n / 1024, 1)} KB"
  defp format_bytes(n), do: "#{Float.round(n / 1024 / 1024, 1)} MB"

  defp format_time(iso) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    dt |> DateTime.add(@vn_offset_seconds, :second) |> Calendar.strftime("%d/%m/%Y %H:%M")
  end

  defp esc(str), do: str |> to_string() |> Plug.HTML.html_escape()
end
