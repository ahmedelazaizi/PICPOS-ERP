// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

/// Handles PLU upload protocol for all supported scale brands.
/// CSV upload framing variant — name + wrapper function.
class _CsvFrame {
  final String name;
  final List<int> Function(List<int> csvBytes) wrap;
  _CsvFrame(this.name, this.wrap);
}

/// Frame wrapper variants tried when uploading PLU to Rongta scales via raw TCP.
/// Different firmwares expect different framing — we try all until one gets ACK.
enum _RongtaFrame {
  /// STX + "0110" + data + ETX + LRC — RLS1000 Software Manual §2.5
  stxCmdDataEtxLrc,
  /// STX + "0110" + data + ETX (no checksum) — some firmwares skip LRC validation
  stxCmdDataEtx,
  /// "0110" + data + CRLF — simplified ASCII line-based
  cmdDataCrLf,
  /// Just data + CRLF — raw PLU record per line (no command code)
  dataCrLf,
}
