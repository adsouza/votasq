import {describe, expect, it} from "vitest";

import {chunkRefs, MAX_BATCH_WRITES} from "./markAllNotificationsRead";

describe("chunkRefs", () => {
  it("returns an empty list when given an empty input", () => {
    expect(chunkRefs([])).toEqual([]);
  });

  it("returns a single chunk when input is smaller than chunk size", () => {
    const refs = [1, 2, 3];
    expect(chunkRefs(refs, 10)).toEqual([[1, 2, 3]]);
  });

  it("splits at exactly the chunk-size boundary", () => {
    const refs = Array.from({length: 1000}, (_, i) => i);
    const chunks = chunkRefs(refs, 500);
    expect(chunks).toHaveLength(2);
    expect(chunks[0]).toHaveLength(500);
    expect(chunks[1]).toHaveLength(500);
    expect(chunks[0][0]).toBe(0);
    expect(chunks[1][0]).toBe(500);
  });

  it("leaves a partial trailing chunk for non-multiples", () => {
    const refs = Array.from({length: 1234}, (_, i) => i);
    const chunks = chunkRefs(refs, MAX_BATCH_WRITES);
    expect(chunks).toHaveLength(3);
    expect(chunks[0]).toHaveLength(500);
    expect(chunks[1]).toHaveLength(500);
    expect(chunks[2]).toHaveLength(234);
  });

  it("rejects a non-positive chunk size", () => {
    expect(() => chunkRefs([1, 2, 3], 0)).toThrow();
    expect(() => chunkRefs([1, 2, 3], -1)).toThrow();
  });
});
