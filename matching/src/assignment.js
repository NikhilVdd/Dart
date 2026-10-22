// Optimal one-to-one assignment of rows (requests) to columns (runners).
//
// solveAssignment() maximises the number of rows assigned first, and only then minimises the total
// cost. It does this by giving every row a private "unassigned" column whose cost is larger than
// any possible difference in real cost, and making forbidden pairs cost more than staying
// unassigned. The Hungarian algorithm then finds the exact optimum in O(n²·m).

/**
 * Hungarian algorithm for a rectangular cost matrix with rows ≤ columns. Every row gets a column.
 * Shortest-augmenting-path form with potentials (1-indexed internally).
 *
 * @param {number[][]} cost  Finite numbers only
 * @returns {number[]} The column for each row
 */
export function hungarian(cost) {
  const n = cost.length;
  if (n === 0) return [];
  const m = cost[0].length;
  if (m < n) throw new RangeError("hungarian() needs at least as many columns as rows");
  if (!cost.every(row => row.length === m && row.every(Number.isFinite))) {
    throw new RangeError("hungarian() needs a rectangular matrix of finite numbers");
  }

  const u = new Array(n + 1).fill(0);
  const v = new Array(m + 1).fill(0);
  const p = new Array(m + 1).fill(0);   // p[j] = row matched to column j
  const way = new Array(m + 1).fill(0);

  for (let i = 1; i <= n; i++) {
    p[0] = i;
    let j0 = 0;
    const minv = new Array(m + 1).fill(Infinity);
    const used = new Array(m + 1).fill(false);
    do {
      used[j0] = true;
      const i0 = p[j0];
      let delta = Infinity;
      let j1 = 0;
      for (let j = 1; j <= m; j++) {
        if (used[j]) continue;
        const reduced = cost[i0 - 1][j - 1] - u[i0] - v[j];
        if (reduced < minv[j]) { minv[j] = reduced; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      for (let j = 0; j <= m; j++) {
        if (used[j]) { u[p[j]] += delta; v[j] -= delta; } else { minv[j] -= delta; }
      }
      j0 = j1;
    } while (p[j0] !== 0);
    do {
      const j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 !== 0);
  }

  const rowToCol = new Array(n).fill(-1);
  for (let j = 1; j <= m; j++) if (p[j] !== 0) rowToCol[p[j] - 1] = j - 1;
  return rowToCol;
}

/**
 * @param {(number | null)[][]} costs  costs[row][col]; null means the pair is not allowed.
 *   Use integers if you need exact tie behaviour.
 * @returns {number[]} The column for each row, or -1 when the row stays unassigned.
 */
export function solveAssignment(costs) {
  const n = costs.length;
  if (n === 0) return [];
  const m = costs[0].length;

  // Any assignment's real cost lies within ±range, so an unassigned row (cost U) always outweighs
  // any rearrangement of real costs, and a forbidden pair (2U) is always worse than unassigned.
  let range = 0;
  for (const row of costs) {
    let rowMax = 0;
    for (const c of row) {
      if (c === null) continue;
      // NaN or Infinity would stall the Hungarian loop instead of failing.
      if (!Number.isFinite(c)) throw new RangeError(`solveAssignment() needs finite costs or null, got ${c}`);
      rowMax = Math.max(rowMax, Math.abs(c));
    }
    range += rowMax;
  }
  const unassigned = 2 * range + 1;
  const forbidden = 2 * unassigned;

  const extended = costs.map(row => [
    ...row.map(c => (c === null ? forbidden : c)),
    ...new Array(n).fill(unassigned)
  ]);
  return hungarian(extended).map((col, row) => (col < m && costs[row][col] !== null ? col : -1));
}
