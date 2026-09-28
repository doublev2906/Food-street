import type { FluidSimulation } from "./vendor/webgl-fluid.js";

type Point = { x: number; y: number };
const TAIL_MS = 1400;
const FADE_MS = 500;
const FRAME_MS = 1000 / 60;

export function createFluidCursor() {
  let canvas: HTMLCanvasElement | null = null;
  let simulation: FluidSimulation | null = null;
  let point: Point | null = null;
  let press: Point | null = null;
  let frame = 0;
  let lastFrame = 0;
  let lastMove = 0;
  let loading = false;
  let failed = false;
  let disposed = false;

  const sizeCanvas = () => {
    if (!canvas) return;
    // A soft fluid trail needs no Retina-sized backing buffer. Bound ultrawide/4K too.
    const scale = Math.min(1, 1920 / Math.max(innerWidth, innerHeight));
    canvas.width = Math.max(1, Math.round(innerWidth * scale));
    canvas.height = Math.max(1, Math.round(innerHeight * scale));
  };

  const pause = () => {
    const wasActive = point !== null;
    cancelAnimationFrame(frame);
    frame = 0;
    lastFrame = 0;
    point = null;
    press = null;
    if (canvas) canvas.style.opacity = "0";
    if (wasActive) simulation?.reset();
  };

  const release = () => {
    canvas?.removeEventListener("webglcontextlost", onContextLost);
    simulation?.dispose();
    simulation = null;
    canvas?.remove();
    canvas = null;
  };

  const onContextLost = () => {
    // Keep the native cursor usable; retry only when this option is selected again.
    failed = true;
    cancelAnimationFrame(frame);
    frame = 0;
    release();
  };

  const tick = (now: number) => {
    frame = 0;
    if (!simulation || !canvas || !point || disposed) return;
    const idle = now - lastMove;
    if (document.hidden || idle >= TAIL_MS) {
      pause();
      return;
    }
    // Coalesce pointer events and cap simulation work on 120/144 Hz displays.
    if (!lastFrame || now - lastFrame >= FRAME_MS - 0.5) {
      const dt = lastFrame ? Math.min((now - lastFrame) / 1000, 1 / 30) : 1 / 60;
      lastFrame = now;
      simulation.move(point.x / innerWidth, point.y / innerHeight);
      if (press) {
        simulation.press(press.x / innerWidth, press.y / innerHeight);
        press = null;
      }
      simulation.advance(dt);
      canvas.style.opacity = String(Math.min(1, (TAIL_MS - idle) / FADE_MS));
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
      const { createFluidSimulation } = await import("./vendor/webgl-fluid.js");
      if (disposed || !point || document.hidden) return;
      canvas = document.createElement("canvas");
      canvas.className = "cursor-fluid";
      canvas.setAttribute("aria-hidden", "true");
      canvas.style.opacity = "0";
      document.body.append(canvas);
      sizeCanvas();
      canvas.addEventListener("webglcontextlost", onContextLost);
      simulation = createFluidSimulation(canvas);
      wake();
    } catch {
      // Unsupported GPU/failed chunk load: the ordinary cursor continues working.
      failed = true;
      release();
    } finally {
      loading = false;
    }
  };

  const resize = () => {
    pause();
    sizeCanvas();
  };
  window.addEventListener("resize", resize, { passive: true });

  return {
    move(x: number, y: number) {
      point = { x, y };
      lastMove = performance.now();
      if (simulation) wake();
      else void load();
    },
    press(x: number, y: number) {
      press = { x, y };
    },
    pause,
    dispose() {
      disposed = true;
      pause();
      window.removeEventListener("resize", resize);
      release();
    },
  };
}
