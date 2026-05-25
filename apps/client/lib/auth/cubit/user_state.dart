enum AuthStatus { unknown, authenticated, unauthenticated }

class UserState {
  const UserState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.remainingVotes,
    this.problemDetailsViewCount,
    this.votesCastCount,
    this.sessionStartLastActiveAt,
  });

  final AuthStatus status;
  final String? userId;
  final int? remainingVotes;

  /// Live count from the user-doc subscription; null until first read.
  final int? problemDetailsViewCount;

  /// Live count from the user-doc subscription; null until first read.
  final int? votesCastCount;

  /// `lastActiveAt` value captured the moment this session began —
  /// frozen for the rest of the session so banner / toast suppression
  /// math doesn't shift as the server's lastActiveAt advances.
  final DateTime? sessionStartLastActiveAt;

  /// Static integer gap between session start and now. Null while
  /// loading. Computed at read-time but anchored to the frozen snapshot.
  int? get _daysSinceLastSession {
    final snap = sessionStartLastActiveAt;
    if (snap == null) return null;
    return DateTime.now().difference(snap).inDays;
  }

  /// True iff the user is authenticated AND has cast few enough votes
  /// (relative to the session-start gap) AND currently has a vote to
  /// spend, so the tip is actionable. Returns false while loading so
  /// the banner doesn't flicker into and out of the vote state on cold
  /// start. The actionable guard means the banner naturally disappears
  /// when the user's budget is exhausted and reappears once
  /// `grantVotesAndTouch` replenishes it — the nudge is only surfaced
  /// when the vote chip is actually tappable.
  bool get needsVoteHint {
    if (status != AuthStatus.authenticated) return false;
    final count = votesCastCount;
    final days = _daysSinceLastSession;
    final votes = remainingVotes;
    if (count == null || days == null || votes == null) return false;
    if (votes <= 0) return false;
    return count <= days;
  }

  /// Same shape as [needsVoteHint] but for the tap-for-details hint.
  bool get needsTapForDetailsHint {
    if (status != AuthStatus.authenticated) return false;
    final count = problemDetailsViewCount;
    final days = _daysSinceLastSession;
    if (count == null || days == null) return false;
    return count <= days;
  }

  UserState copyWith({
    AuthStatus? status,
    String? Function()? userId,
    int? Function()? remainingVotes,
    int? Function()? problemDetailsViewCount,
    int? Function()? votesCastCount,
    DateTime? Function()? sessionStartLastActiveAt,
  }) {
    return UserState(
      status: status ?? this.status,
      userId: userId != null ? userId() : this.userId,
      remainingVotes: remainingVotes != null
          ? remainingVotes()
          : this.remainingVotes,
      problemDetailsViewCount: problemDetailsViewCount != null
          ? problemDetailsViewCount()
          : this.problemDetailsViewCount,
      votesCastCount: votesCastCount != null
          ? votesCastCount()
          : this.votesCastCount,
      sessionStartLastActiveAt: sessionStartLastActiveAt != null
          ? sessionStartLastActiveAt()
          : this.sessionStartLastActiveAt,
    );
  }
}
