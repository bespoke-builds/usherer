import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/tourist_group.dart';
import '../../data/models/tourist.dart';
import '../../data/models/flight.dart';
import '../../app_config.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream all groups for a date - attach on dashboard init
  // Securely gates data loading based on whether a sheet URL is actively configured
  Stream<List<TouristGroup>> watchGroups(String date) async* {
    final sessionDoc = _firestore.collection('sessions').doc(date);
    await for (final sessionSnap in sessionDoc.snapshots()) {
      final data = sessionSnap.data();
      final sheetId = data?['spreadsheetId'] as String?;

      if (sheetId == null || sheetId.trim().isEmpty) {
        yield <TouristGroup>[];
      } else {
        yield* sessionDoc.collection('groups').snapshots().map((snapshot) {
          return snapshot.docs.map((doc) {
            return TouristGroup.fromMap(doc.data(), doc.id);
          }).toList();
        });
      }
    }
  }

  // Set the full group data (used during initial sync from Google Sheets)
  Future<void> syncGroup(String date, TouristGroup group) async {
    final sheetId = AppConfig.spreadsheetId;

    // Write spreadsheet ID and active flag to parent document to make it discoverable
    await _firestore.collection('sessions').doc(date).set({
      'active': true,
      'spreadsheetId': sheetId,
    }, SetOptions(merge: true));

    await _firestore
        .collection('sessions')
        .doc(date)
        .collection('groups')
        .doc(group.id)
        .set(group.toMap());
  }

  // Performs a single batch operation to sync all groups without clearing them first
  // This prevents the UI from refreshing completely when a new app instance connects
  Future<void> syncAllGroups(String date, List<TouristGroup> groups) async {
    final sheetId = AppConfig.spreadsheetId;

    final batch = _firestore.batch();

    // Write spreadsheet ID and active flag to parent document to make it discoverable
    batch.set(
      _firestore.collection('sessions').doc(date),
      {
        'active': true,
        'spreadsheetId': sheetId,
      },
      SetOptions(merge: true),
    );

    final collectionRef = _firestore
        .collection('sessions')
        .doc(date)
        .collection('groups');

    // Fetch existing documents to find stale groups
    final existingSnap = await collectionRef.get();
    final newGroupIds = groups.map((g) => g.id).toSet();

    for (final doc in existingSnap.docs) {
      if (!newGroupIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    // Create/update current groups
    for (final group in groups) {
      batch.set(collectionRef.doc(group.id), group.toMap());
    }

    await batch.commit();
  }

  // Any coordinator - mark tourist status (pickup/dropoff)
  // Use arrayRemove + arrayUnion pattern for nested tourist updates
  Future<void> markTouristStatus({
    required String date,
    required String groupId,
    required String touristId,
    required String field,
    required bool value,
  }) async {
    final docRef = _firestore
        .collection('sessions')
        .doc(date)
        .collection('groups')
        .doc(groupId);

    final docSnap = await docRef.get();
    if (!docSnap.exists) return;

    final data = docSnap.data();
    if (data == null) return;

    final group = TouristGroup.fromMap(data, docSnap.id);
    Tourist? targetTourist;

    for (var tourist in group.tourists) {
      if (tourist.id == touristId) {
        targetTourist = tourist;
        break;
      }
    }

    if (targetTourist == null) return;

    // Capture old state map for removal
    final oldTouristMap = targetTourist.toMap();

    // Create new state
    bool newPickUp = targetTourist.pickUp;
    bool newDropOff = targetTourist.dropOff;
    if (field == 'pickup') {
      newPickUp = value;
    } else if (field == 'dropoff') {
      newDropOff = value;
    }

    final timestampString = (newPickUp || newDropOff)
        ? DateTime.now().toIso8601String()
        : null;

    final updatedTourist = targetTourist.copyWith(
      pickUp: newPickUp,
      dropOff: newDropOff,
      hasArrived: newPickUp && newDropOff, // Fully complete when both are true
      arrivedAt: timestampString,
      markedBy: 'Coordinator',
    );

    // Atomic array update in Firestore
    await _firestore.runTransaction((transaction) async {
      transaction.update(docRef, {
        'tourists': FieldValue.arrayRemove([oldTouristMap]),
      });
      transaction.update(docRef, {
        'tourists': FieldValue.arrayUnion([updatedTourist.toMap()]),
      });
    });
  }

  // Any coordinator - update tourist notes dynamically
  Future<void> updateTouristNote({
    required String date,
    required String groupId,
    required String touristId,
    required String note,
  }) async {
    final docRef = _firestore
        .collection('sessions')
        .doc(date)
        .collection('groups')
        .doc(groupId);

    final docSnap = await docRef.get();
    if (!docSnap.exists) return;

    final data = docSnap.data();
    if (data == null) return;

    final group = TouristGroup.fromMap(data, docSnap.id);
    Tourist? targetTourist;

    for (var tourist in group.tourists) {
      if (tourist.id == touristId) {
        targetTourist = tourist;
        break;
      }
    }

    if (targetTourist == null) return;

    // Capture old state map for removal
    final oldTouristMap = targetTourist.toMap();

    final updatedTourist = targetTourist.copyWith(notes: note);

    // Atomic array update in Firestore
    await _firestore.runTransaction((transaction) async {
      transaction.update(docRef, {
        'tourists': FieldValue.arrayRemove([oldTouristMap]),
      });
      transaction.update(docRef, {
        'tourists': FieldValue.arrayUnion([updatedTourist.toMap()]),
      });
    });
  }

  // Admin Workmanager task only - update Live ETA and Flight Status
  Future<void> updateGroupEta({
    required String date,
    required String groupId,
    required String liveEta,
    required FlightStatus status,
  }) async {
    await _firestore
        .collection('sessions')
        .doc(date)
        .collection('groups')
        .doc(groupId)
        .update({'liveEta': liveEta, 'flightStatus': status.toShortString()});
  }

  // Clear all groups for a specific date session before doing a fresh Sheets sync
  Future<void> clearGroupsForDate(String date) async {
    // 1. Delete the session document itself (including the spreadsheetId field)
    await _firestore
        .collection('sessions')
        .doc(date)
        .delete()
        .catchError((_) {});

    // 2. Delete all sub-documents in the groups collection
    final collectionRef = _firestore
        .collection('sessions')
        .doc(date)
        .collection('groups');
    final snapshots = await collectionRef.get();
    final batch = _firestore.batch();
    for (final doc in snapshots.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // Admin Kill Switch: Wipes all data across all dates using collectionGroup query
  Future<void> wipeEntireDatabase() async {
    final batch = _firestore.batch();

    // 1. Delete all parent session documents
    final sessionsSnap = await _firestore.collection('sessions').get();
    for (final doc in sessionsSnap.docs) {
      batch.delete(doc.reference);
    }

    // 2. Delete all sub-documents in all groups collections
    final groupsSnap = await _firestore.collectionGroup('groups').get();
    for (final doc in groupsSnap.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  // Fetch the remote spreadsheet ID from Firestore config
  Future<String?> getRemoteSpreadsheetId() async {
    try {
      final doc = await _firestore.collection('config').doc('system').get();
      return doc.data()?['spreadsheetId'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Set or clear the remote spreadsheet ID in Firestore config
  Future<void> setRemoteSpreadsheetId(String? id) async {
    if (id == null) {
      await _firestore
          .collection('config')
          .doc('system')
          .delete()
          .catchError((_) {});
    } else {
      await _firestore.collection('config').doc('system').set({
        'spreadsheetId': id,
      }, SetOptions(merge: true));
    }
  }
}
