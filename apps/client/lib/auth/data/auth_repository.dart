import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn = kIsWeb ? null : (googleSignIn ?? GoogleSignIn());

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn? _googleSignIn;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  bool get isAuthenticated => _firebaseAuth.currentUser != null;

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      return _firebaseAuth.signInWithPopup(GoogleAuthProvider());
    }
    final googleUser = await _googleSignIn!.signIn();
    if (googleUser == null) {
      throw Exception('Google Sign-In was cancelled');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (kIsWeb) {
      await _firebaseAuth.signOut();
    } else {
      await Future.wait([
        _firebaseAuth.signOut(),
        _googleSignIn!.signOut(),
      ]);
    }
  }
}
