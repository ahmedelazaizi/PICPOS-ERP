// In-memory fakes shared by the credential-stamp / offline-policy tests.
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';

class MemSecure implements OfflineLoginStore {
  String? json;
  bool failing = false;
  @override
  Future<String?> read() async {
    if (failing) throw StateError('no secure storage');
    return json;
  }

  @override
  Future<void> write(String j) async {
    if (failing) throw StateError('no secure storage');
    json = j;
  }
}

class MemBacking implements StampBacking {
  final Map<String, String> values = {};
  bool failing = false;

  /// Throws on the n-th write (1-based) - interruption simulation.
  int? failOnWrite;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (failing) throw StateError('disk gone');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failing) throw StateError('disk gone');
    writes++;
    if (failOnWrite != null && writes == failOnWrite) {
      throw StateError('interrupted');
    }
    values[key] = value;
  }
}
