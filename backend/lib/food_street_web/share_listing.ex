defmodule FoodStreetWeb.ShareListing do
  @moduledoc """
  Trang danh sách thư mục `/share/...` (HTML tĩnh, không script — CSP chỉ cho style inline).

  Màu lấy theo token của app (`frontend/src/index.css`: theme sáng + dark). Trang này không
  đọc được theme người dùng chọn trong app (localStorage, không có script) nên theo
  `prefers-color-scheme` của máy.
  """

  alias FoodStreet.SharedPages

  @vn_offset_seconds 7 * 3600

  @style """
  :root{color-scheme:light;--bg:#f4f6f8;--surface:#fff;--border:#e3e8ee;--text:#1a2b3c;
    --muted:#6b7c8f;--primary:#e8590c;--primary-text:#e8590c;--primary-soft:#fff1e8;
    --hover:#eef2f6;--grad-hi:#ff9a4d;--accent-shadow:rgba(232,89,12,.12);
    --shadow:0 1px 3px rgba(16,24,40,.08),0 1px 2px rgba(16,24,40,.04)}
  @media (prefers-color-scheme:dark){:root{color-scheme:dark;--bg:#141b25;--surface:#212b38;
    --border:#364252;--text:#eaf0f6;--muted:#9fb0c1;--primary:#e96b26;--primary-text:#ffaa70;
    --primary-soft:#3a2413;--hover:#2e3a49;--grad-hi:#f57d3b;--accent-shadow:rgba(0,0,0,.3);
    --shadow:0 1px 3px rgba(0,0,0,.4),0 1px 2px rgba(0,0,0,.3)}}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,
    BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
  a{color:inherit;text-decoration:none}
  header{background:var(--surface);border-bottom:1px solid var(--border);height:60px;
    display:flex;align-items:center;padding:0 24px}
  .brand{display:flex;align-items:center;gap:10px;font-weight:800;font-size:19px}
  .brand-logo{width:34px;height:34px;border-radius:10px;display:grid;place-items:center;
    font-size:18px;background:linear-gradient(135deg,var(--grad-hi),var(--primary));
    box-shadow:0 2px 8px var(--accent-shadow)}
  .brand-accent{color:var(--primary-text)}
  main{max-width:960px;margin:28px auto;padding:0 16px}
  .head{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;
    flex-wrap:wrap;margin-bottom:14px}
  h1{font-size:22px;margin:0 0 4px;line-height:1.25}
  .muted{color:var(--muted)}.small{font-size:13px}
  .crumbs{display:flex;flex-wrap:wrap;align-items:center;gap:4px}
  .crumb{padding:3px 10px;border-radius:99px;font-size:13px;font-weight:600;
    color:var(--muted);border:1px solid transparent}
  a.crumb:hover{background:var(--hover);color:var(--text)}
  .crumb.current{background:var(--primary-soft);color:var(--primary-text)}
  .sep{color:var(--muted);font-size:13px}
  .card{background:var(--surface);border:1px solid var(--border);border-radius:10px;
    box-shadow:var(--shadow);overflow:hidden}
  table{width:100%;border-collapse:collapse;font-size:14px}
  th{text-align:left;padding:10px 14px;border-bottom:2px solid var(--border);color:var(--muted);
    font-size:12px;text-transform:uppercase;letter-spacing:.03em}
  td{padding:10px 14px;border-bottom:1px solid var(--border);vertical-align:middle}
  tr:last-child td{border-bottom:none}
  tbody tr:hover td{background:var(--hover)}
  .name{display:flex;align-items:center;gap:12px;font-weight:600;word-break:break-word}
  .name:hover{color:var(--primary-text)}
  .ic{width:34px;height:34px;flex-shrink:0;border-radius:9px;display:grid;place-items:center;
    font-size:17px;background:var(--hover)}
  .folder .ic{background:var(--primary-soft)}
  .num{white-space:nowrap;color:var(--muted);font-size:13px;font-variant-numeric:tabular-nums}
  .empty{text-align:center;padding:48px 20px}
  .empty-ic{width:72px;height:72px;margin:0 auto 10px;border-radius:50%;display:grid;
    place-items:center;font-size:34px;background:var(--primary-soft)}
  @media (max-width:640px){header{padding:0 14px;height:54px}main{margin:18px auto;padding:0 10px}
    td,th{padding:9px 10px}.col-size{display:none}}
  """

  def render(%{dir: dir, folders: folders, files: files}) do
    body =
      if folders == [] and files == [] and dir == "" do
        empty()
      else
        [
          ~s(<table><thead><tr><th>Tên</th><th class="col-size">Dung lượng</th>),
          ~s(<th>Cập nhật</th></tr></thead><tbody>),
          parent_row(dir),
          Enum.map(folders, &row/1),
          Enum.map(files, &row/1),
          if(folders == [] and files == [],
            do: ~s(<tr><td colspan="3" class="muted small">Thư mục trống.</td></tr>),
            else: ""
          ),
          "</tbody></table>"
        ]
      end

    [
      """
      <!doctype html>
      <html lang="vi"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>#{esc(title(dir))} · Food Street</title>
      <style>#{@style}</style></head><body>
      <header><div class="brand"><span class="brand-logo">🍜</span>
      <span>Food <span class="brand-accent">Street</span></span></div></header>
      <main><div class="head"><div><h1>🔗 Trang chia sẻ</h1>
      <nav class="crumbs">#{breadcrumb(dir)}</nav></div>
      <div class="muted small">#{summary(folders, files)}</div></div>
      <div class="card">
      """,
      body,
      "</div></main></body></html>"
    ]
  end

  defp empty do
    ~s(<div class="empty"><div class="empty-ic">📂</div><strong>Chưa có trang nào</strong>) <>
      ~s(<div class="muted small">Admin upload trang HTML ở mục "Chia sẻ HTML" ) <>
      ~s(trong app.</div></div>)
  end

  defp parent_row(""), do: ""

  defp parent_row(dir) do
    parent = dir |> String.split("/", trim: true) |> Enum.drop(-1) |> Enum.join("/")
    href = esc(SharedPages.url_for(parent, :folder))

    ~s(<tr><td colspan="3"><a class="name" href="#{href}"><span class="ic">↩</span>) <>
      ~s(<span class="muted">Lên thư mục trên</span></a></td></tr>)
  end

  defp row(entry) do
    {icon, size, cls, suffix} =
      if entry.type == :folder,
        do: {"📁", "—", "folder", "/"},
        else: {"📄", format_bytes(entry.size), "file", ""}

    time = format_time(entry.updated_at)

    ~s(<tr class="#{cls}"><td><a class="name" href="#{esc(entry.url)}">) <>
      ~s(<span class="ic">#{icon}</span><span>#{esc(entry.name)}#{suffix}</span></a></td>) <>
      ~s(<td class="num col-size">#{size}</td><td class="num">#{time}</td></tr>)
  end

  defp summary(folders, files) do
    [{length(folders), "thư mục"}, {length(files), "trang"}]
    |> Enum.reject(fn {n, _} -> n == 0 end)
    |> Enum.map_join(" · ", fn {n, label} -> "#{n} #{label}" end)
  end

  defp title(""), do: "share"
  defp title(dir), do: "share/" <> dir

  defp breadcrumb(dir) do
    segments = String.split(dir, "/", trim: true)
    last = length(segments)

    crumbs =
      segments
      |> Enum.with_index(1)
      |> Enum.map(fn {seg, i} ->
        crumb =
          if i == last do
            ~s(<span class="crumb current">#{esc(seg)}</span>)
          else
            href = segments |> Enum.take(i) |> Enum.join("/") |> SharedPages.url_for(:folder)
            ~s(<a class="crumb" href="#{esc(href)}">#{esc(seg)}</a>)
          end

        ~s(<span class="sep">/</span>) <> crumb
      end)

    root_cls = if segments == [], do: "crumb current", else: "crumb"
    ~s(<a class="#{root_cls}" href="/share/">📁 share</a>) <> Enum.join(crumbs)
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
