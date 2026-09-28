const SVG_NS = "http://www.w3.org/2000/svg";
const SEGMENTS = 32;
const SIZE = 520;
const FRAME_MS = 1000 / 60;
const REST_MS = 1600;
const FADE_MS = 500;
type Point = { x: number; y: number };
type Segment = Point & { node: SVGUseElement; wings: boolean };

export function createDragonCursor() {
  let layer: HTMLDivElement | null = null;
  let svg: SVGSVGElement | null = null;
  let point: Point | null = null;
  const head = { x: 0, y: 0 };
  const segments: Segment[] = [];
  let frame = 0;
  let lastFrame = 0;
  let lastMove = 0;
  let pressedAt = -Infinity;
  let phase = 0;
  let scale = 0.34;
  let interactive = false;
  let resetPose = true;
  let loading = false;
  let failed = false;
  let disposed = false;

  const pause = () => {
    cancelAnimationFrame(frame);
    frame = 0;
    lastFrame = 0;
    point = null;
    resetPose = true;
    pressedAt = -Infinity;
    if (layer) layer.hidden = true;
  };

  const pose = () => {
    if (!point) return;
    head.x = point.x;
    head.y = point.y;
    // Lúc hiện lại, trải đuôi về tâm màn hình để tránh quét từ vị trí cũ qua trang.
    const angle = Math.atan2(innerHeight / 2 - point.y, innerWidth / 2 - point.x);
    let previous = head;
    for (const [i, segment] of segments.entries()) {
      const gap = (20 - i * 0.25) * scale;
      segment.x = previous.x + Math.cos(angle) * gap;
      segment.y = previous.y + Math.sin(angle) * gap;
      previous = segment;
    }
    resetPose = false;
  };

  const tick = (now: number) => {
    frame = 0;
    if (!point || !layer || !svg || disposed) return;
    const idle = now - lastMove;
    if (document.hidden || idle >= REST_MS) {
      pause();
      return;
    }

    // Gom sự kiện chuột vào một nhịp vẽ; giới hạn 60 fps cả trên màn hình 144 Hz.
    if (!lastFrame || now - lastFrame >= FRAME_MS - 0.5) {
      const dt = lastFrame ? Math.min((now - lastFrame) / FRAME_MS, 2) : 1;
      lastFrame = now;
      scale += ((interactive ? 0.23 : 0.34) - scale) * (1 - Math.pow(0.8, dt));
      if (resetPose) pose();

      const distance = Math.hypot(point.x - head.x, point.y - head.y);
      const energy = Math.min(1, distance / 100);
      const headEase = 1 - Math.pow(0.76, dt);
      head.x += (point.x - head.x) * headEase;
      head.y += (point.y - head.y) * headEase;
      phase += (0.055 + energy * 0.07) * dt;

      let previous = head;
      for (const [i, segment] of segments.entries()) {
        const angle = Math.atan2(segment.y - previous.y, segment.x - previous.x);
        const gap = (20 - i * 0.25) * scale;
        // Giữ chiều dài các đốt để rê nhanh không kéo giãn rồng ra khỏi khung vẽ.
        segment.x = previous.x + Math.cos(angle) * gap;
        segment.y = previous.y + Math.sin(angle) * gap;
        const taper = 3.1 * (1 - i / SEGMENTS) + 0.06;
        const s = taper * scale;
        const flap = segment.wings ? 0.83 + Math.sin(phase + i * 0.3) * (0.07 + energy * 0.1) : 1;
        const x = (previous.x + segment.x) / 2 - head.x + SIZE / 2;
        const y = (previous.y + segment.y) / 2 - head.y + SIZE / 2;
        segment.node.setAttribute("transform",
          `translate(${x.toFixed(2)} ${y.toFixed(2)}) rotate(${(angle * 180 / Math.PI).toFixed(2)}) scale(${s.toFixed(3)} ${(s * flap).toFixed(3)})`);
        previous = segment;
      }

      const flare = now - pressedAt < 280;
      if (layer.hasAttribute("data-flare") !== flare) layer.toggleAttribute("data-flare", flare);
      layer.hidden = false;
      svg.style.transform = `translate3d(${(head.x - SIZE / 2).toFixed(1)}px, ${(head.y - SIZE / 2).toFixed(1)}px, 0)`;
      svg.style.opacity = String(Math.min(1, (REST_MS - idle) / FADE_MS) * (interactive ? 0.62 : 0.92));
    }
    frame = requestAnimationFrame(tick);
  };

  const wake = () => {
    if (!frame) frame = requestAnimationFrame(tick);
  };

  const load = async () => {
    if (loading || failed || disposed) return;
    loading = true;
    try {
      const { default: artwork } = await import("./assets/dragon.svg?raw");
      if (disposed || !point || document.hidden) return;
      const template = document.createElement("template");
      template.innerHTML = artwork;
      svg = template.content.querySelector("svg")!;
      svg.classList.add("cursor-dragon");
      svg.setAttribute("aria-hidden", "true");
      svg.setAttribute("focusable", "false");
      const body = document.createElementNS(SVG_NS, "g");
      body.classList.add("cursor-dragon-body");
      svg.append(body);
      for (let i = 0; i < SEGMENTS; i++) {
        const node = document.createElementNS(SVG_NS, "use");
        const wings = i === 6 || i === 12;
        node.setAttribute("href", `#fs-dragon-${i === 0 ? "head" : wings ? "wings" : "spine"}`);
        body.prepend(node);
        segments.push({ x: 0, y: 0, node, wings });
      }
      layer = document.createElement("div");
      layer.className = "cursor-dragon-layer";
      layer.hidden = true;
      layer.setAttribute("aria-hidden", "true");
      layer.append(svg);
      document.body.append(layer);
      wake();
    } catch {
      failed = true;
      layer?.remove();
      layer = null;
      svg = null;
      segments.length = 0;
    } finally {
      loading = false;
    }
  };

  window.addEventListener("resize", pause, { passive: true });

  return {
    move(x: number, y: number, overControl: boolean) {
      point = { x, y };
      interactive = overControl;
      lastMove = performance.now();
      if (layer) wake();
      else void load();
    },
    press() {
      pressedAt = performance.now();
    },
    pause,
    dispose() {
      disposed = true;
      pause();
      window.removeEventListener("resize", pause);
      layer?.remove();
      layer = null;
      svg = null;
      segments.length = 0;
    },
  };
}
