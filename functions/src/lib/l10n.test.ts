import {beforeEach, describe, expect, it} from "vitest";

import {_clearCacheForTesting, format, loadStrings} from "./l10n";

describe("format", () => {
  it("substitutes named placeholders", () => {
    expect(
      format("{actorName} voted on your problem", {actorName: "Alice"}),
    ).toBe("Alice voted on your problem");
  });

  it("leaves the template alone when no params are needed", () => {
    expect(format("A problem you voted on has a new version")).toBe(
      "A problem you voted on has a new version",
    );
  });

  it("supports multiple placeholders in one string", () => {
    expect(
      format("{actorName} linked {problem} from another", {
        actorName: "Bob",
        problem: "issue-42",
      }),
    ).toBe("Bob linked issue-42 from another");
  });

  it("leaves unknown placeholders intact so the bug surfaces visibly", () => {
    expect(format("{actorName} voted", {})).toBe("{actorName} voted");
  });
});

describe("loadStrings", () => {
  beforeEach(() => {
    _clearCacheForTesting();
  });

  it("loads English strings synced from the client ARB", () => {
    const en = loadStrings("en");
    expect(en).toHaveProperty(
      "notificationVoteReceivedTitle",
      "New vote",
    );
    expect(en).toHaveProperty(
      "notificationVoteReceivedBody",
      "{actorName} voted on your problem",
    );
  });

  it("falls back to English when a locale ARB is missing", () => {
    // No ARB for 'xx' exists; the loader silently falls back.
    const result = loadStrings("xx");
    expect(result).toHaveProperty(
      "notificationVoteReceivedTitle",
      "New vote",
    );
  });

  it("does not include @-prefixed metadata entries", () => {
    const en = loadStrings("en");
    expect(en).not.toHaveProperty("@notificationVoteReceivedTitle");
  });
});
