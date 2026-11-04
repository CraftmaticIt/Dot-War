// Building definitions (port of meta/buildings.gd). Index = level - 1.
export const TYPES = ["core", "mine", "storage", "generator", "laser", "pulse", "wall", "trap"];
export const MAX_LEVEL = 5;
const MAX_NODES = [8, 11, 14, 17, 20];

const TABLE: Record<string, Record<string, number[]>> = {
  core: { cost: [0, 1000, 4000, 12000, 30000], secs: [0, 300, 3600, 14400, 43200], energy_cap: [2000, 3000, 5000, 8000, 15000] },
  mine: { cost: [100, 300, 800, 2000, 5000], secs: [10, 60, 300, 1800, 7200], energy_per_hour: [500, 1000, 1750, 2750, 4000] },
  storage: { cost: [150, 400, 1000, 2500, 6000], secs: [10, 90, 600, 2400, 7200], energy_cap: [1500, 3000, 5000, 8000, 12000] },
  generator: { cost: [200, 500, 1200, 3000, 7000], secs: [20, 120, 600, 2400, 9000],
    dots_per_hour: [300, 600, 1000, 1500, 2250], dots_cap: [50, 80, 120, 170, 230] },
  laser: { cost: [250, 600, 1500, 3500, 8000], secs: [30, 180, 900, 3600, 10800] },
  pulse: { cost: [250, 600, 1500, 3500, 8000], secs: [30, 180, 900, 3600, 10800] },
  wall: { cost: [50, 150, 400, 1000, 2500], secs: [5, 30, 180, 900, 3600] },
  trap: { cost: [100, 250, 600, 1500, 3500], secs: [10, 60, 300, 1200, 3600] },
};

export const isType = (t: string): boolean => Object.hasOwn(TABLE, t);
function field(t: string, f: string, level: number): number {
  if (level < 1 || level > MAX_LEVEL || !isType(t)) return 0;
  const row = TABLE[t][f] ?? [];
  return row.length >= level ? row[level - 1] : 0;
}
export const cost = (t: string, l: number) => field(t, "cost", l);
export const buildSecs = (t: string, l: number) => field(t, "secs", l);
export const energyPerHour = (t: string, l: number) => field(t, "energy_per_hour", l);
export const dotsPerHour = (t: string, l: number) => field(t, "dots_per_hour", l);
export const energyCap = (t: string, l: number) => field(t, "energy_cap", l);
export const dotsCap = (t: string, l: number) => field(t, "dots_cap", l);
export const maxNodes = (coreLevel: number) => MAX_NODES[Math.min(Math.max(coreLevel, 1), MAX_LEVEL) - 1];
export const tower = (t: string) => (t === "laser" || t === "pulse" ? t : "");

export function garrison(t: string, level: number): number {
  if (level < 1 || !isType(t)) return 0;
  if (t === "core") return 30 * level;
  if (t === "wall") return 25 * level;
  return 6 * level;
}
export const battleProd = (t: string, l: number) => ((t === "core" || t === "generator") && l >= 1 ? l : 0);
export const trapDmg = (t: string, l: number) => (t === "trap" && l >= 1 ? 10 * l : 0);
