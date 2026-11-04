// Deterministic xorshift32 (port of sim/rng.gd). All ops are uint32.
const ZERO_SEED = 2463534242;

export class SimRng {
  private state: number;

  constructor(seed: number) {
    this.state = Number(BigInt.asUintN(32, BigInt(Math.trunc(seed))));
    if (this.state === 0) this.state = ZERO_SEED;
  }

  nextU32(): number {
    let x = this.state;
    x = (x ^ (x << 13)) >>> 0;
    x = (x ^ (x >>> 17)) >>> 0;
    x = (x ^ (x << 5)) >>> 0;
    this.state = x;
    return x;
  }

  rangeI(n: number): number {
    return this.nextU32() % n;
  }
}
