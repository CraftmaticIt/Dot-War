// Axial hex coordinates (port of meta/hex.gd).
import { idiv } from "../sim/fx.ts";

export const SIZE = 2000;
export const DIRS: [number, number][] = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];

export const key = (q: number, r: number): string => `${q},${r}`;
export function parse(k: string): [number, number] {
  const p = String(k).split(",");
  const n = (s: string | undefined) => { const v = Math.trunc(Number(s)); return Number.isFinite(v) ? v : 0; };
  return [n(p[0]), n(p[1])];
}
export const neighbors = (q: number, r: number): [number, number][] => DIRS.map(([dq, dr]) => [q + dq, r + dr]);
export const toFx = (q: number, r: number): { x: number; y: number } =>
  ({ x: idiv(SIZE * (1732 * q + 866 * r), 1000), y: idiv(SIZE * (1500 * r), 1000) });
