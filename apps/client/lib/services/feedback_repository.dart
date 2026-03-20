import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Submits user feedback: screenshot to Firebase Storage,
/// metadata to Firestore.
class FeedbackRepository {
  FeedbackRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  static const _collection = 'feedback';

  /// Uploads [screenshot] to Storage and writes [text] + metadata to Firestore.
  Future<void> submit({
    required String text,
    required Uint8List screenshot,
    required String userId,
  }) async {
    final id = const Uuid().v4();
    final storagePath = '$_collection/$id.png';

    await _storage
        .ref(storagePath)
        .putData(
          screenshot,
          SettableMetadata(contentType: 'image/png'),
        );

    await _firestore.collection(_collection).doc(id).set({
      'text': text,
      'screenshotPath': storagePath,
      'userId': userId,
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }
}
