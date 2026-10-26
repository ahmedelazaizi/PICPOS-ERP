// PICPOS_DATA_DIR: كل موضع دائم يُحسم من DataDir، ولا تغيير للافتراضي.
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picpos_erp/core/config/data_dir.dart';
import 'package:picpos_erp/core/config/data_dir_plugins.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'docs');
  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'sup');
}

void main() {
  late Directory tmp;
  late PathProviderPlatform savedPp;
  late SharedPreferencesStorePlatform savedPrefs;
  late FlutterSecureStoragePlatform savedSecure;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('data_dir_test_');
    savedPp = PathProviderPlatform.instance;
    savedPrefs = SharedPreferencesStorePlatform.instance;
    savedSecure = FlutterSecureStoragePlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    DataDir.debugEnvironment = null;
    PathProviderPlatform.instance = savedPp;
    SharedPreferencesStorePlatform.instance = savedPrefs;
    FlutterSecureStoragePlatform.instance = savedSecure;
    tmp.deleteSync(recursive: true);
  });

  test('unset: default locations come from path_provider, no plugin files',
      () async {
    DataDir.debugEnvironment = const {};
    expect(DataDir.isOverridden, isFalse);
    final m = await DataDir.resolvedLocations();
    expect(m['documents'], p.join(tmp.path, 'docs'));
    expect(m['support'], p.join(tmp.path, 'sup'));
    expect(m['prefsFile'], isNull);
    expect(m['secureFile'], isNull);
    // blank value counts as unset
    DataDir.debugEnvironment = {DataDir.envName: '  '};
    expect(DataDir.isOverridden, isFalse);
  });

  test('unset: roamingAppData keeps %APPDATA% (or ".")', () {
    DataDir.debugEnvironment = const {};
    expect(DataDir.roamingAppData(),
        Platform.environment['APPDATA'] ?? '.');
  });

  test('set: every location lives under the override directory', () async {
    final root = p.join(tmp.path, 'lab', 'data');
    DataDir.debugEnvironment = {DataDir.envName: root};
    final m = await DataDir.resolvedLocations();
    expect(m.length, 5, reason: 'new location must be added to the test');
    for (final e in m.entries) {
      expect(p.isWithin(root, e.value!) || p.equals(root, e.value!), isTrue,
          reason: '${e.key} = ${e.value} escapes $root');
    }
    expect(m['documents'], root);
    // the redirected path_provider locations must not be used
    expect(m.values.any((v) => v!.contains('${p.separator}docs')), isFalse);
  });

  test('relative override is rejected loudly (never falls back to real data)',
      () {
    DataDir.debugEnvironment = {DataDir.envName: 'relative/dir'};
    expect(() => DataDir.overridePath, throwsStateError);
  });

  test('plugin redirects: prefs + secure storage persist inside the override',
      () async {
    final root = p.join(tmp.path, 'lab2');
    DataDir.debugEnvironment = {DataDir.envName: root};
    installDataDirPluginRedirects();

    final prefs = SharedPreferencesStorePlatform.instance;
    await prefs.setValue('String', 'flutter.k', 'v');
    await prefs.setValue('StringList', 'flutter.l', ['a', 'b']);
    expect((await prefs.getAll())['flutter.k'], 'v');
    expect((await prefs.getAll())['flutter.l'], ['a', 'b']);
    await prefs.remove('flutter.k');
    expect((await prefs.getAll()).containsKey('flutter.k'), isFalse);

    final sec = FlutterSecureStoragePlatform.instance;
    await sec.write(key: 'k', value: 'secret', options: const {});
    expect(await sec.read(key: 'k', options: const {}), 'secret');
    expect(await sec.containsKey(key: 'k', options: const {}), isTrue);
    await sec.delete(key: 'k', options: const {});
    expect(await sec.read(key: 'k', options: const {}), isNull);

    expect(File(DataDir.prefsFilePath!).existsSync(), isTrue);
    expect(File(DataDir.secureFilePath!).existsSync(), isTrue);
    expect(p.isWithin(root, DataDir.prefsFilePath!), isTrue);
    expect(p.isWithin(root, DataDir.secureFilePath!), isTrue);
  });

  test('plugin redirects are a no-op when unset', () {
    DataDir.debugEnvironment = const {};
    final before = SharedPreferencesStorePlatform.instance;
    final beforeSecure = FlutterSecureStoragePlatform.instance;
    installDataDirPluginRedirects();
    expect(identical(SharedPreferencesStorePlatform.instance, before), isTrue);
    expect(identical(FlutterSecureStoragePlatform.instance, beforeSecure),
        isTrue);
  });
}
