enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.remainingVotes,
  });

  final AuthStatus status;
  final String? userId;
  final int? remainingVotes;

  AuthState copyWith({
    AuthStatus? status,
    String? Function()? userId,
    int? Function()? remainingVotes,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId != null ? userId() : this.userId,
      remainingVotes: remainingVotes != null
          ? remainingVotes()
          : this.remainingVotes,
    );
  }
}
