import {describe, expect, it, beforeEach, vi} from "vitest";

import firebaseFunctionsTest from "firebase-functions-test";

const testEnv = firebaseFunctionsTest();

const updateMock = vi.fn();
const docMock = vi.fn(() => ({update: updateMock}));
vi.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({doc: docMock}),
  FieldValue: {
    increment: (n: number) => ({__op: "increment", n}),
  },
}));

beforeEach(() => {
  updateMock.mockReset();
  docMock.mockClear();
});

describe("onVoterWrittenForVotesCastCount", () => {
  it("voter-create with votes:1 increments votesCastCount by 1", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 1},
      "problems/p1/voters/u1",
    );
    const change = testEnv.makeChange(null, after);
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({data: change, params: {pid: "p1", actorUid: "u1"}});

    expect(docMock).toHaveBeenCalledWith("users/u1");
    expect(updateMock).toHaveBeenCalledWith({
      votesCastCount: {__op: "increment", n: 1},
    });
  });

  it("voter-update from votes:3 to votes:5 increments votesCastCount by 2", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 5}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).toHaveBeenCalledWith({
      votesCastCount: {__op: "increment", n: 2},
    });
  });

  it("voter-update with no votes change is a no-op", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).not.toHaveBeenCalled();
  });

  it("voter-update where votes decreased is a no-op (monotonic)", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 5}, "problems/p1/voters/u1",
    );
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).not.toHaveBeenCalled();
  });

  it("voter-delete is a no-op", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, null),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).not.toHaveBeenCalled();
  });
});
