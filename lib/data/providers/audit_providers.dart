import 'package:flutter_riverpod/flutter_riverpod.dart';
export '../../services/activity_logger.dart';
import 'providers.dart';

/// Provider for the forensic activity logging service
final activityLoggerProvider = Provider<ActivityLogger>((ref) {
  final db = ref.watch(databaseProvider);
  return ActivityLogger(db);
});
