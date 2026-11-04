// Fixed-point integer math (port of sim/fx.gd). Scale ONE = 1000.
// Contract: GDScript int `/` truncates toward zero -> idiv uses Math.trunc (never Math.floor).
export const ONE = 1000;

export function idiv(a: number, b: number): number {
  return Math.trunc(a / b);
}

export function fromInt(i: number): number {
  return i * ONE;
}

export function mul(a: number, b: number): number {
  return idiv(a * b, ONE);
}

export function div(a: number, b: number): number {
  return idiv(a * ONE, b);
}

export function isqrt(n: number): number {
  if (n <= 0) return 0;
  let x = n;
  let y = idiv(x + 1, 2);
  while (y < x) {
    x = y;
    y = idiv(x + idiv(n, x), 2);
  }
  return x;
}

export function dist(ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax;
  const dy = by - ay;
  return isqrt(dx * dx + dy * dy);
}
