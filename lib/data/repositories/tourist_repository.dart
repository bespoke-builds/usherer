import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/tourist_group.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/sheets_service.dart';
import '../local/hive_cache.dart';
import 'flight_repository.dart';
import '../../app_config.dart';

class TouristRepository {
  static final FirestoreService _firestoreService = FirestoreService();
  static final SheetsService _sheetsService = SheetsService();

  // Broadcast when a wipe happens so controllers can instantly clear their in-memory state
  static final ValueNotifier<int> wipeNotifier = ValueNotifier(0);

  // Load from Sheets, sync to Firestore, cache in Hive
  static Future<void> loadAndSyncFromSheets(String date) async {
    try {
      // 1. Fetch the remote spreadsheet ID from Firestore first to sync state across devices
      final remoteId = await _firestoreService.getRemoteSpreadsheetId();
      
      // If the remote ID is null/empty, it means the database was wiped or no sheet is active!
      if (remoteId == null || remoteId.trim().isEmpty) {
        await HiveCache.setSpreadsheetId(null);
        AppConfig.setSpreadsheetIdOverride(null);
        return; // Skip syncing completely!
      }

      // Sync local Hive cache to match the remote source of truth
      if (HiveCache.getSpreadsheetId() != remoteId) {
        await HiveCache.setSpreadsheetId(remoteId);
      }

      final sheetId = AppConfig.spreadsheetId;
      if (sheetId == null || sheetId.isEmpty) {
        throw Exception("No Google Sheet link/ID configured. Please configure it in the Settings screen first.");
      }

      final groups = await _sheetsService.fetchSheetData(date);

      // Sync all groups in a single batch operation without clearing first
      // This prevents connected clients from refreshing their UI completely
      await _firestoreService.syncAllGroups(date, groups);

      // Sort chronologically by scheduled time ascending
      groups.sort((a, b) {
        final timeCompare = a.scheduledTime.compareTo(b.scheduledTime);
        if (timeCompare != 0) return timeCompare;
        return (a.sheetRow ?? 0).compareTo(b.sheetRow ?? 0);
      });

      // Cache in Hive
      await HiveCache.cacheGroups(groups);

      // Check if user is Admin, then poll flight updates instantly in the foreground!
      const storage = FlutterSecureStorage();
      final isAdmin = await storage.read(key: 'isAdmin') == 'true';
      if (isAdmin) {
        print(
          'TouristRepository: Admin verified. Triggering foreground live flight poll.',
        );
        // Run in background thread (fire-and-forget) so we don't block visual sheets sync
        FlightRepository.pollFlights(date, groups).catchError((error) {
          print('Foreground live flight poll failed: $error');
        });
      }
    } catch (e) {
      print('TouristRepository loadAndSyncFromSheets error: $e');
      rethrow;
    }
  }

  // Watch Firestore stream and automatically mirror data to Hive local cache
  static Stream<List<TouristGroup>> watchGroups(String date) {
    return _firestoreService.watchGroups(date).map((groups) {
      // Sort chronologically by scheduled time ascending
      groups.sort((a, b) {
        final timeCompare = a.scheduledTime.compareTo(b.scheduledTime);
        if (timeCompare != 0) return timeCompare;
        return (a.sheetRow ?? 0).compareTo(b.sheetRow ?? 0);
      });

      // Proactively update local cache on every snapshot
      HiveCache.cacheGroups(groups);
      return groups;
    });
  }

  // Update tourist check-in status: Firestore immediately, Sheets fire-and-forget
  static Future<void> markTouristStatus({
    required String date,
    required String groupId,
    required String touristId,
    required String field, // 'pickup' or 'dropoff'
    required bool value,
    required int? sheetRow,
  }) async {
    // 1. Live state write to Firestore (Primary)
    await _firestoreService.markTouristStatus(
      date: date,
      groupId: groupId,
      touristId: touristId,
      field: field,
      value: value,
    );

    // 2. Permanent record write to Sheets (Fire-and-forget in background)
    if (sheetRow != null) {
      _sheetsService.writeTouristStatus(date, sheetRow, field, value).catchError((
        error,
      ) {
        print('Background Sheets sync failed for tourist $touristId: $error');
      });
    }
  }

  // Update tourist notes: Firestore immediately, Sheets fire-and-forget
  static Future<void> updateTouristNote({
    required String date,
    required String groupId,
    required String touristId,
    required String note,
    required int? sheetRow,
  }) async {
    // 1. Live state write to Firestore (Primary)
    await _firestoreService.updateTouristNote(
      date: date,
      groupId: groupId,
      touristId: touristId,
      note: note,
    );

    // 2. Permanent record write to Sheets (Fire-and-forget in background)
    if (sheetRow != null) {
      _sheetsService.writeTouristNote(date, sheetRow, note).catchError((
        error,
      ) {
        print('Background Sheets sync failed for tourist note $touristId: $error');
      });
    }
  }

  // Admin Kill Switch: Wipes all Firestore data for all dates, local cache, and sheet ID
  static Future<void> wipeAllData() async {
    final activeDate = HiveCache.getCurrentDate('');

    // 1. Wipe Firestore active date immediately (guaranteed targeted delete)
    if (activeDate.isNotEmpty) {
      try {
        await _firestoreService.clearGroupsForDate(activeDate);
      } catch (e) {
        print('Error during targeted active date wipe: $e');
      }
    }

    // 2. Wipe all other sessions in Firestore globally (safe collection group delete)
    try {
      await _firestoreService.wipeEntireDatabase();
    } catch (e) {
      print('Global wipeEntireDatabase failed (possibly due to security rules): $e');
    }
    
    // 3. Clear remote spreadsheet ID in Firestore config
    try {
      await _firestoreService.setRemoteSpreadsheetId(null);
    } catch (e) {
      print('Failed to clear remote spreadsheet ID: $e');
    }
    
    // 4. Clear local Hive cache
    await HiveCache.groupsBox.clear();
    
    // 5. Clear the Google Sheet ID from persistent storage AND in-memory override
    await HiveCache.setSpreadsheetId(null);
    AppConfig.setSpreadsheetIdOverride(null);

    // 5. Signal all listening controllers to clear their in-memory state immediately
    wipeNotifier.value++;
  }
}
