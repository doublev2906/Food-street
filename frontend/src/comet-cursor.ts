type Point = { x: number; y: number };
type Spark = Point & { vx: number; vy: number; born: number; color: number };

export function createCometCursor() {
  const size = 480;
  const center = size / 2;
  const colors = ["#06b6d4", "#8b5cf6", "#ec4899"];
  const layer = document.createElement("div");
  layer.className = "cursor-comet-layer";
  layer.setAttribute("aria-hidden", "true");
  const canvas = document.createElement("canvas");
  canvas.className = "cursor-comet";
  canvas.setAttribute("aria-hidden", "true");
  canvas.hidden = true;
  const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
  canvas.width = canvas.height = size * ratio;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;
  ctx.scale(ratio, ratio);
  layer.append(canvas);
  document.body.append(layer);

  // Glow vẽ sẵn; canvas chỉ phủ 480px quanh chuột thay vì raster cả màn hình.
  const glows = colors.map((color) => {
    const glow = document.createElement("canvas");
    glow.width = glow.height = 64;
    const context = glow.getContext("2d")!;
    const gradient = context.createRadialGradient(32, 32, 0, 32, 32, 32);
    gradient.addColorStop(0, "#ffffff");
    gradient.addColorStop(0.12, color);
    gradient.addColorStop(1, `${color}00`);
    context.fillStyle = gradient;
    context.fillRect(0, 0, 64, 64);
    return glow;
  });
  let points: Point[] = [];
  let sparks: Spark[] = [];
  let rings: (Point & { born: number })[] = [];
  let pointer = { x: 0, y: 0, interactive: false };
  let sampled: Point = { x: 0, y: 0 };
  let paintId = 0;
  let lastMove = 0;
  let lastPaint = 0;

  const addSpark = (x: number, y: number, vx: number, vy: number, born: number) => {
    if (sparks.length === 32) sparks.shift();
    sparks.push({ x, y, vx, vy, born, color: Math.floor(Math.random() * colors.length) });
  };
  const paint = (now: number) => {
    paintId = 0;
    if (now - lastPaint < 1000 / 60 - 1) {
      paintId = requestAnimationFrame(paint);
      return;
    }
    const step = Math.min(2, (now - lastPaint) / (1000 / 60));
    lastPaint = now;
    const fade = Math.max(0, 1 - (now - lastMove) / 700);
    sparks = sparks.filter((spark) => now - spark.born < 600);
    rings = rings.filter((ring) => now - ring.born < 480);
    ctx.clearRect(0, 0, size, size);
    if (!fade && !sparks.length && !rings.length) {
      canvas.hidden = true;
      return;
    }
    canvas.hidden = false;
    canvas.style.transform = `translate3d(${pointer.x - center}px, ${pointer.y - center}px, 0)`;
    const dx = pointer.x - sampled.x;
    const dy = pointer.y - sampled.y;
    if (Math.hypot(dx, dy) > 4) {
      addSpark(pointer.x, pointer.y, -dx * 0.015 + Math.random() - 0.5, -dy * 0.015 + Math.random() - 0.5, now);
    }
    sampled = { x: pointer.x, y: pointer.y };
    points[0] = { x: pointer.x, y: pointer.y };
    const follow = 1 - Math.pow(0.58, step);
    for (let i = 1; i < points.length; i++) {
      points[i].x += (points[i - 1].x - points[i].x) * follow;
      points[i].y += (points[i - 1].y - points[i].y) * follow;
    }
    ctx.lineCap = "round";
    for (let layer = 0; layer < 2; layer++) {
      for (let i = 1; i < points.length - 1; i++) {
        const p = points[i];
        const previous = points[i - 1];
        const next = points[i + 1];
        const distance = Math.hypot(p.x - pointer.x, p.y - pointer.y);
        const taper = (1 - i / points.length) * Math.max(0, 1 - (distance / 215) ** 4);
        if (taper <= 0) continue;
        ctx.globalAlpha = fade * taper * (layer ? 0.8 : 0.12);
        ctx.strokeStyle = colors[Math.floor(i / 8) % colors.length];
        ctx.lineWidth = (layer ? 3 : 16) * taper;
        ctx.beginPath();
        ctx.moveTo((previous.x + p.x) / 2 - pointer.x + center, (previous.y + p.y) / 2 - pointer.y + center);
        ctx.quadraticCurveTo(p.x - pointer.x + center, p.y - pointer.y + center,
          (p.x + next.x) / 2 - pointer.x + center, (p.y + next.y) / 2 - pointer.y + center);
        ctx.stroke();
      }
    }
    for (const spark of sparks) {
      spark.x += spark.vx * step;
      spark.y += spark.vy * step;
      const progress = (now - spark.born) / 600;
      const distance = Math.hypot(spark.x - pointer.x, spark.y - pointer.y);
      ctx.globalAlpha = (1 - progress) * Math.max(0, 1 - (distance / 215) ** 4);
      const radius = 9 * (1 - progress) + 3;
      ctx.drawImage(glows[spark.color], spark.x - pointer.x + center - radius, spark.y - pointer.y + center - radius, radius * 2, radius * 2);
    }
    for (const ring of rings) {
      const progress = (now - ring.born) / 480;
      const distance = Math.hypot(ring.x - pointer.x, ring.y - pointer.y);
      ctx.globalAlpha = (1 - progress) * 0.65 * Math.max(0, 1 - (distance / 180) ** 4);
      ctx.strokeStyle = colors[0];
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(ring.x - pointer.x + center, ring.y - pointer.y + center, 6 + progress * 38, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = fade * 0.65;
    const radius = pointer.interactive ? 23 : 15;
    ctx.drawImage(glows[0], center - radius, center - radius, radius * 2, radius * 2);
    ctx.globalAlpha = 1;
    paintId = requestAnimationFrame(paint);
  };
  const move = (x: number, y: number, interactive: boolean) => {
    if (canvas.hidden) {
      points = Array.from({ length: 28 }, () => ({ x, y }));
      sampled = { x, y };
    }
    pointer = { x, y, interactive };
    lastMove = performance.now();
    if (!paintId) paintId = requestAnimationFrame(paint);
  };
  const pause = () => {
    cancelAnimationFrame(paintId);
    paintId = 0;
    sparks = [];
    rings = [];
    canvas.hidden = true;
  };
  return {
    move,
    press: (x: number, y: number) => {
      const now = performance.now();
      if (rings.length === 3) rings.shift();
      rings.push({ x, y, born: now });
      for (let i = 0; i < 12; i++) {
        const angle = (i / 12) * Math.PI * 2;
        addSpark(x, y, Math.cos(angle) * 2, Math.sin(angle) * 2, now);
      }
    },
    pause,
    dispose: () => {
      pause();
      layer.remove();
    },
  };
}
