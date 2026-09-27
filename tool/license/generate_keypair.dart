import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:ural_erp/core/utils/license_encoding.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/license/generate_keypair.dart <private-key-path>');
    exitCode = 64;
    return;
  }

  final outputPath = File(arguments.single).absolute.path;
  final allowedDirectory = _normalise(Directory('tools/picpos-activation').absolute.path);
  if (!_normalise(outputPath).startsWith('$allowedDirectory${Platform.pathSeparator}')) {
    stderr.writeln('Refusing to write a private key outside tools/picpos-activation/.');
    exitCode = 77;
    return;
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKey = await keyPair.extract();
  await File(outputPath).writeAsString(encodeUnpaddedBase64Url(privateKey.bytes));
  final publicKey = await keyPair.extractPublicKey();
  stdout.writeln('Public key (base64url): ${encodeUnpaddedBase64Url(publicKey.bytes)}');
}

String _normalise(String path) =>
    path.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator);
