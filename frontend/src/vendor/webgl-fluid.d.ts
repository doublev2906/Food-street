export interface FluidSimulation {
  /** Coordinates normalized to the viewport, with the origin at the top left. */
  move(x: number, y: number): void;
  press(x: number, y: number): void;
  advance(dt: number): void;
  reset(): void;
  dispose(): void;
}

export function createFluidSimulation(canvas: HTMLCanvasElement): FluidSimulation;
