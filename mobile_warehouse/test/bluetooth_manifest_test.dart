// WH-015: the Android manifest declares Bluetooth the Android 12+ way. Parses the
// source manifest; the MERGED manifest (plugin entries) is checked with aapt2 in
// the device lab.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<Map<String, String>> _permissions(String xml) => [
      for (final m in RegExp(r'<uses-permission\s+([^>]*?)/?>', dotAll: true).allMatches(xml))
        {for (final a in RegExp(r'([\w:]+)="([^"]*)"').allMatches(m.group(1)!)) a.group(1)!: a.group(2)!},
    ];

void main() {
  final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final perms = _permissions(xml);
  Map<String, String>? perm(String name) =>
      perms.where((p) => p['android:name'] == 'android.permission.$name').firstOrNull;

  test('legacy Bluetooth permissions stop at Android 11 and win over the plugin\'s', () {
    for (final n in ['BLUETOOTH', 'BLUETOOTH_ADMIN']) {
      expect(perm(n), isNotNull, reason: n);
      expect(perm(n)!['android:maxSdkVersion'], '30', reason: n);
      expect(perm(n)!['tools:node'], 'replace', reason: '$n: the plugin declares it without a limit');
    }
  });

  test('BLUETOOTH_CONNECT is declared (runtime permission of paired printers)', () {
    expect(perm('BLUETOOTH_CONNECT'), isNotNull);
  });

  test('BLUETOOTH_SCAN, if declared, is neverForLocation and replaces the plugin\'s entry', () {
    final scan = perm('BLUETOOTH_SCAN');
    expect(scan, isNotNull);
    expect(scan!['android:usesPermissionFlags'], 'neverForLocation');
    expect(scan['tools:node'], 'replace');
  });

  test('no location permission is required to print', () {
    expect(perm('ACCESS_FINE_LOCATION'), isNull);
    expect(perm('ACCESS_COARSE_LOCATION'), isNull);
  });

  test('Bluetooth hardware is optional (the app also prints to a network printer)', () {
    expect(xml, contains('android.hardware.bluetooth'));
    expect(RegExp(r'android.hardware.bluetooth"\s+android:required="false"').hasMatch(xml), isTrue);
  });

  test('the Kotlin side asks only for BLUETOOTH_CONNECT and answers on the channel the app uses', () {
    final kt = File('android/app/src/main/kotlin/com/picpos/warehouse/MainActivity.kt').readAsStringSync();
    expect(kt, contains('com.picpos.warehouse/bluetooth_permission'));
    expect(kt, contains('requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT)'));
    expect(kt, isNot(contains('ACCESS_FINE_LOCATION')));
    final dart = File('lib/main.dart').readAsStringSync();
    expect(dart, contains('MethodChannelBluetoothPermissionGate()'));
  });
}