import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { hungarian, solveAssignment } from "../src/assignment.js";

// Small deterministic PRNG so the random cases are the same on every run.
function mulberry32(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Exhaustive search: fewest unassigned rows first, then lowest total cost. */
function bruteForce(costs) {
  const m = costs[0]?.length ?? 0;
  let best = { unassigned: Infinity, total: Infinity };
  const walk = (row, used, unassigned, total) => {
    if (row === costs.length) {
      if (unassigned < best.unassigned || (unassigned === best.unassigned && total < best.total)) best = { unassigned, total };
      return;
    }
    walk(row + 1, used, unassigned + 1, total);
    for (let col = 0; col < m; col++) {
      if (used.has(col) || costs[row][col] === null) continue;
      used.add(col);
      walk(row + 1, used, unassigned, total + costs[row][col]);
      used.delete(col);
    }
  };
  walk(0, new Set(), 0, 0);
  return best;
}

function objective(costs, columns) {
  let unassigned = 0;
  let total = 0;
  columns.forEach((col, row) => { if (col < 0) unassigned++; else total += costs[row][col]; });
  return { unassigned, total };
}

describe("assignment", () => {
  test("hungarian finds the minimum-cost assignment", () => {
    const cost = [[4, 1, 3], [2, 0, 5], [3, 2, 2]];
    const cols = hungarian(cost);
    assert.equal(cols.reduce((sum, c, r) => sum + cost[r][c], 0), 5);
    assert.equal(new Set(cols).size, 3);
  });

  test("covering more rows beats a lower total cost", () => {
    // Row 0 is cheapest on column 0, but row 1 can only use column 0.
    assert.deepEqual(solveAssignment([[1, 100], [1, null]]), [1, 0]);
  });

  test("rows with no allowed column stay unassigned", () => {
    assert.deepEqual(solveAssignment([[null, null], [3, 4]]), [-1, 0]);
  });

  test("more rows than columns leaves the costliest rows unassigned", () => {
    assert.deepEqual(solveAssignment([[5], [1], [3]]), [-1, 0, -1]);
  });

  test("negative costs (stability bonuses) are handled", () => {
    assert.deepEqual(solveAssignment([[-50, 1], [2, -50]]), [0, 1]);
  });

  test("matches brute force on 300 random matrices", () => {
    const rand = mulberry32(20261021);
    for (let k = 0; k < 300; k++) {
      const n = 1 + Math.floor(rand() * 5);
      const m = 1 + Math.floor(rand() * 5);
      const costs = Array.from({ length: n }, () => Array.from({ length: m }, () =>
        (rand() < 0.3 ? null : Math.floor(rand() * 40) - 5)));
      const cols = solveAssignment(costs);
      const used = cols.filter(c => c >= 0);
      assert.equal(new Set(used).size, used.length, "a column is used twice");
      cols.forEach((c, r) => { if (c >= 0) assert.notEqual(costs[r][c], null, "forbidden pair chosen"); });
      assert.deepEqual(objective(costs, cols), bruteForce(costs), `matrix ${JSON.stringify(costs)}`);
    }
  });

  test("non-finite costs are refused instead of looping forever", () => {
    assert.throws(() => solveAssignment([[NaN, 1]]), /finite costs/);
    assert.throws(() => solveAssignment([[Infinity]]), /finite costs/);
    assert.throws(() => hungarian([[1, NaN]]), /finite numbers/);
  });

  test("empty input", () => {
    assert.deepEqual(solveAssignment([]), []);
    assert.deepEqual(hungarian([]), []);
  });
});
