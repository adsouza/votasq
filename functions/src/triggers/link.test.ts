import {describe, expect, it, beforeEach, vi} from "vitest";
import firebaseFunctionsTest from "firebase-functions-test";

const testEnv = firebaseFunctionsTest();

// Owner lookups: docMock("problems/<id>").get() resolves to a snapshot
// whose `.get("ownerId")` returns whatever this map has for <id>.
const ownerById = new Map<string, string>();
const docMock = vi.fn((path: string) => ({
  get: async () => ({
    get: (field: string) => {
      if (field !== "ownerId") return undefined;
      const id = path.split("/").pop() ?? "";
      return ownerById.get(id);
    },
  }),
}));

vi.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({doc: docMock}),
  FieldValue: {serverTimestamp: () => ({__op: "serverTimestamp"})},
}));

// writeNotification is mocked at the module level so we can assert what
// payload was emitted to which recipient without exercising the real
// preference + create plumbing (that's covered in notify.test.ts).
const writeNotificationMock = vi.fn(async () => true);
vi.mock("../lib/notify", () => ({
  writeNotification: (uid: string, payload: unknown) =>
    writeNotificationMock(uid, payload),
}));

beforeEach(() => {
  docMock.mockClear();
  writeNotificationMock.mockClear();
  ownerById.clear();
});

interface ProblemDocFields {
  ownerId?: string;
  lastLinkActor?: string;
  linkedProblemIds?: string[];
  typedLinks?: Array<{targetId: string; kind: string}>;
}

function snap(
  id: string,
  fields: ProblemDocFields | null,
): ReturnType<typeof testEnv.firestore.makeDocumentSnapshot> | null {
  if (fields === null) return null;
  return testEnv.firestore.makeDocumentSnapshot(fields, `problems/${id}`);
}

describe("onProblemLinkedWritten", () => {
  it("emits ONE notification to the counterparty when the actor's side " +
    "fires (lastLinkActor present)", async () => {
    const {onProblemLinkedWritten} = await import("./link");
    // User X (owner of A) generic-links A to B (owned by Y). The trigger
    // fires for the doc whose owner is the actor; the recipient is Y.
    ownerById.set("A", "X");
    ownerById.set("B", "Y");

    const wrapped = testEnv.wrap(onProblemLinkedWritten);
    const before = snap("A", {
      ownerId: "X",
      linkedProblemIds: [],
      typedLinks: [],
    });
    const after = snap("A", {
      ownerId: "X",
      lastLinkActor: "X",
      linkedProblemIds: ["B"],
      typedLinks: [],
    });
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {linkerId: "A"},
    });

    expect(writeNotificationMock).toHaveBeenCalledOnce();
    expect(writeNotificationMock).toHaveBeenCalledWith("Y", {
      type: "problemLinked",
      linkedProblemId: "B",
      linkerProblemId: "A",
      actorUid: "X",
      kind: null,
    });
  });

  it("filters out the mirrored-side firing of a paired write " +
    "(recipient == lastLinkActor)", async () => {
    const {onProblemLinkedWritten} = await import("./link");
    // Same link as above, but now we simulate the OTHER trigger firing
    // — the one on B's doc. Before the fix, B's ownerId (Y) was used as
    // the actor; with lastLinkActor (X) stamped, the recipient (X) ==
    // the actor (X), so the filter skips the notification entirely.
    ownerById.set("A", "X");
    ownerById.set("B", "Y");

    const wrapped = testEnv.wrap(onProblemLinkedWritten);
    const before = snap("B", {
      ownerId: "Y",
      linkedProblemIds: [],
      typedLinks: [],
    });
    const after = snap("B", {
      ownerId: "Y",
      lastLinkActor: "X",
      linkedProblemIds: ["A"],
      typedLinks: [],
    });
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {linkerId: "B"},
    });

    expect(writeNotificationMock).not.toHaveBeenCalled();
  });

  it("falls back to ownerId when lastLinkActor is missing " +
    "(backward compat for pre-existing docs)", async () => {
    const {onProblemLinkedWritten} = await import("./link");
    ownerById.set("A", "X");
    ownerById.set("B", "Y");

    const wrapped = testEnv.wrap(onProblemLinkedWritten);
    const before = snap("A", {
      ownerId: "X",
      linkedProblemIds: [],
      typedLinks: [],
    });
    // No lastLinkActor field — simulates a doc written before this fix
    // shipped. The trigger should still attribute the action using
    // ownerId, preserving the previous behavior on the side where it
    // happens to coincide with the actor.
    const after = snap("A", {
      ownerId: "X",
      linkedProblemIds: ["B"],
      typedLinks: [],
    });
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {linkerId: "A"},
    });

    expect(writeNotificationMock).toHaveBeenCalledWith("Y", {
      type: "problemLinked",
      linkedProblemId: "B",
      linkerProblemId: "A",
      actorUid: "X",
      kind: null,
    });
  });

  it("emits a typed notification with kind when typedLinks gains an entry",
    async () => {
      const {onProblemLinkedWritten} = await import("./link");
      // User X (owner of A) tags A with `{targetId: B, kind:
      // specialization}`. The trigger fires on A's side; the typed-link
      // diff sees one new entry. Recipient is owner of B; kind passes
      // through directly (matches the recipient-perspective ARB string).
      ownerById.set("A", "X");
      ownerById.set("B", "Y");

      const wrapped = testEnv.wrap(onProblemLinkedWritten);
      const before = snap("A", {
        ownerId: "X",
        linkedProblemIds: [],
        typedLinks: [],
      });
      const after = snap("A", {
        ownerId: "X",
        lastLinkActor: "X",
        linkedProblemIds: [],
        typedLinks: [{targetId: "B", kind: "specialization"}],
      });
      await wrapped({
        data: testEnv.makeChange(before, after),
        params: {linkerId: "A"},
      });

      expect(writeNotificationMock).toHaveBeenCalledOnce();
      expect(writeNotificationMock).toHaveBeenCalledWith("Y", {
        type: "problemLinked",
        linkedProblemId: "B",
        linkerProblemId: "A",
        actorUid: "X",
        kind: "specialization",
      });
    });

  it("filters the mirrored typedLinks firing (same dedup as generic path)",
    async () => {
      const {onProblemLinkedWritten} = await import("./link");
      // Mirror of the above: trigger fires on B's side, sees its
      // inverse entry `{targetId: A, kind: generalization}` added.
      // Recipient = ownerOf(A) = X = lastLinkActor → skipped.
      ownerById.set("A", "X");
      ownerById.set("B", "Y");

      const wrapped = testEnv.wrap(onProblemLinkedWritten);
      const before = snap("B", {
        ownerId: "Y",
        linkedProblemIds: [],
        typedLinks: [],
      });
      const after = snap("B", {
        ownerId: "Y",
        lastLinkActor: "X",
        linkedProblemIds: [],
        typedLinks: [{targetId: "A", kind: "generalization"}],
      });
      await wrapped({
        data: testEnv.makeChange(before, after),
        params: {linkerId: "B"},
      });

      expect(writeNotificationMock).not.toHaveBeenCalled();
    });

  it("does not emit on typedLinks removal (untag is silent)", async () => {
    const {onProblemLinkedWritten} = await import("./link");
    ownerById.set("A", "X");
    ownerById.set("B", "Y");

    const wrapped = testEnv.wrap(onProblemLinkedWritten);
    const before = snap("A", {
      ownerId: "X",
      lastLinkActor: "X",
      linkedProblemIds: [],
      typedLinks: [{targetId: "B", kind: "specialization"}],
    });
    const after = snap("A", {
      ownerId: "X",
      lastLinkActor: "X",
      linkedProblemIds: [],
      typedLinks: [],
    });
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {linkerId: "A"},
    });

    expect(writeNotificationMock).not.toHaveBeenCalled();
  });

  it("emits both notifications when typedLinks gain entries to two " +
    "different recipients in a single write", async () => {
    const {onProblemLinkedWritten} = await import("./link");
    // Edge case: a single batch could add typed entries to multiple
    // targets from the same source doc (e.g., re-tagging an existing
    // pair while adding a fresh one). Each new entry should fan out.
    ownerById.set("A", "X");
    ownerById.set("B", "Y");
    ownerById.set("C", "Z");

    const wrapped = testEnv.wrap(onProblemLinkedWritten);
    const before = snap("A", {
      ownerId: "X",
      linkedProblemIds: [],
      typedLinks: [],
    });
    const after = snap("A", {
      ownerId: "X",
      lastLinkActor: "X",
      linkedProblemIds: [],
      typedLinks: [
        {targetId: "B", kind: "specialization"},
        {targetId: "C", kind: "generalization"},
      ],
    });
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {linkerId: "A"},
    });

    expect(writeNotificationMock).toHaveBeenCalledTimes(2);
    expect(writeNotificationMock).toHaveBeenCalledWith("Y", {
      type: "problemLinked",
      linkedProblemId: "B",
      linkerProblemId: "A",
      actorUid: "X",
      kind: "specialization",
    });
    expect(writeNotificationMock).toHaveBeenCalledWith("Z", {
      type: "problemLinked",
      linkedProblemId: "C",
      linkerProblemId: "A",
      actorUid: "X",
      kind: "generalization",
    });
  });

  it("skips when the actor owns the linked problem (self-link via clique)",
    async () => {
      const {onProblemLinkedWritten} = await import("./link");
      // X owns both A and B and links them. ownerOf(B) === actor → skip.
      ownerById.set("A", "X");
      ownerById.set("B", "X");

      const wrapped = testEnv.wrap(onProblemLinkedWritten);
      const before = snap("A", {
        ownerId: "X",
        linkedProblemIds: [],
        typedLinks: [],
      });
      const after = snap("A", {
        ownerId: "X",
        lastLinkActor: "X",
        linkedProblemIds: ["B"],
        typedLinks: [],
      });
      await wrapped({
        data: testEnv.makeChange(before, after),
        params: {linkerId: "A"},
      });

      expect(writeNotificationMock).not.toHaveBeenCalled();
    });
});
