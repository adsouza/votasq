import {describe, expect, it} from "vitest";

import {deterministicId} from "./notify";

describe("deterministicId", () => {
  it("collapses identical voteReceived emissions to one id", () => {
    expect(
      deterministicId({
        type: "voteReceived",
        problemId: "p1",
        actorUid: "u1",
      }),
    ).toBe("voteReceived__p1__u1");
  });

  it("is stable across all five payload variants", () => {
    expect(
      deterministicId({
        type: "problemForked",
        originalProblemId: "orig",
        forkProblemId: "fork",
        actorUid: "u1",
      }),
    ).toBe("problemForked__fork");
    expect(
      deterministicId({
        type: "problemLinked",
        linkedProblemId: "linked",
        linkerProblemId: "linker",
        actorUid: "u1",
      }),
    ).toBe("problemLinked__linked__linker");
    expect(
      deterministicId({
        type: "problemRevised",
        problemId: "p1",
        newVersion: 3,
      }),
    ).toBe("problemRevised__p1__v3");
    expect(
      deterministicId({
        type: "forkAdopted",
        forkProblemId: "fork",
        originalProblemId: "orig",
        newVersion: 2,
      }),
    ).toBe("forkAdopted__fork__orig__v2");
  });

  it("uses only stable id components — different actors with the same problem give different ids", () => {
    const id1 = deterministicId({
      type: "voteReceived",
      problemId: "p1",
      actorUid: "alice",
    });
    const id2 = deterministicId({
      type: "voteReceived",
      problemId: "p1",
      actorUid: "bob",
    });
    expect(id1).not.toBe(id2);
  });
});
