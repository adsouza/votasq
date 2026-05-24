import {describe, expect, it} from "vitest";

import {computeVotesCastCounts, type UserRow, type VoterRow} from "./backfill_votes_cast_count";

describe("computeVotesCastCounts", () => {
  it("user with no voter docs gets 0", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 0});
  });

  it("user with one voter doc votes:1 gets 1", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [{uid: "u1", votes: 1}];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 1});
  });

  it("user with multiple multi-vote voter docs sums correctly", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [
      {uid: "u1", votes: 3},
      {uid: "u1", votes: 7},
      {uid: "u1", votes: 1},
    ];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 11});
  });

  it("does not mistakenly attribute voter docs to other users", () => {
    const users: UserRow[] = [{uid: "u1"}, {uid: "u2"}];
    const voters: VoterRow[] = [{uid: "u1", votes: 5}];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 5, u2: 0});
  });

  it("ignores voter docs whose uid doesn't match any user", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [{uid: "u-ghost", votes: 99}];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 0});
  });
});
