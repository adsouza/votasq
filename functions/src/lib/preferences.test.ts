import {describe, expect, it} from "vitest";

import {resolveOptIn} from "./preferences";
import type {NotificationPreferences} from "./types";

describe("resolveOptIn (mirrors the Dart helper's defaults)", () => {
  it("applies channel defaults when nothing is stored", () => {
    const empty: NotificationPreferences = {};
    expect(resolveOptIn(empty, "voteReceived", "inApp")).toBe(true);
    expect(resolveOptIn(empty, "voteReceived", "push")).toBe(true);
    expect(resolveOptIn(empty, "voteReceived", "email")).toBe(false);
  });

  it("honors explicitly stored opt-outs", () => {
    const prefs: NotificationPreferences = {
      perType: {
        voteReceived: {push: false, email: true},
      },
    };
    expect(resolveOptIn(prefs, "voteReceived", "push")).toBe(false);
    expect(resolveOptIn(prefs, "voteReceived", "email")).toBe(true);
    // Unspecified channel falls back to the default.
    expect(resolveOptIn(prefs, "voteReceived", "inApp")).toBe(true);
  });

  it("a missing type entry uses the channel defaults", () => {
    const prefs: NotificationPreferences = {
      perType: {
        problemForked: {inApp: false},
      },
    };
    expect(resolveOptIn(prefs, "voteReceived", "inApp")).toBe(true);
  });

  it("undefined prefs object yields defaults", () => {
    expect(resolveOptIn(undefined, "voteReceived", "inApp")).toBe(true);
    expect(resolveOptIn(undefined, "voteReceived", "email")).toBe(false);
  });
});
