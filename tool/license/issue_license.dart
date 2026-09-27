import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:ural_erp/core/utils/license_encoding.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: dart run tool/license/issue_license.dart <private-key-path> <machine-id>');
    exitCode = 64;
    return;
  }

  final privateKeyText = await File(arguments[0]).readAsString();
  final seed = base64Url.decode(_pad(privateKeyText.trim()));
  if (seed.length != 32) {
    stderr.writeln('The private key file must contain one Ed25519 seed.');
    exitCode = 65;
    return;
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final payload = utf8.encode(jsonEncode(<String, Object>{
    'v': 2,
    'machineId': arguments[1],
    'issuedAt': DateTime.now().toUtc().toIso8601String(),
  }));
  final signature = await algorithm.sign(payload, keyPair: keyPair);
  stdout.writeln(
    'PP2-${encodeUnpaddedBase64Url(payload)}.${encodeUnpaddedBase64Url(signature.bytes)}',
  );
}

String _pad(String value) => value.padRight((value.length + 3) ~/ 4 * 4, '=');
