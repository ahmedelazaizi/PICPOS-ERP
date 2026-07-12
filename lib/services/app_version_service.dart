import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/constants/app_constants.dart';

/// ISS-CODE-02: Reads the real app version from the platform (pubspec.yaml)
/// and updates [AppConstants.appVersion] / [AppConstants.appBuildNumber].
///
/// Call [AppVersionService.initialize()] once at startup (before `runApp`).
class AppVersionService {
  AppVersionService._();

  static Future<void> initialize() async {
    try {
      final info = await PackageInfo.fromPlatform();
      AppConstants.appVersion = info.version;
      AppConstants.appBuildNumber = info.buildNumber;
    } catch (e) {
      debugPrint('[AppVersion] Failed to read PackageInfo: $e — using defaults');
    }
  }
}
