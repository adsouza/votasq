enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.userId,
  });

  final AuthStatus status;
  final String? userId;

  AuthState copyWith({
    AuthStatus? status,
    String? Function()? userId,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId != null ? userId() : this.userId,
    );
  }
}
