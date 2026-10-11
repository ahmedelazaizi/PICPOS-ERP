// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: unintended_html_in_doc_comment
part of '../scale_protocols.dart';

// Brand dispatch: maps LabelScaleBrand to its upload implementation

extension _BrandDispatch on ScaleProtocolHandler {
  Future<PLUUploadResult> _dispatchBrand(
    LabelScaleBrand brand,
    List<ScalePLUItem> items,
    LabelScaleConnection connection,
    String? ip, int? port, String? com, int? baud,
    int? dataBits, String? parity, String? stopBits,
  ) async {
    // ── AclasSDK: unified IP-only upload for ALL brands ──
    // The port (if provided by the user) is used as a first-try hint for UDP
    // discovery; the isolate still falls back to common Aclas ports on miss.
    if (connection == LabelScaleConnection.aclasSDK) {
      return _uploadViaAclasSDK(items, ip, customUdpPort: port);
    }

    switch (brand) {
      case LabelScaleBrand.cas:
        return _uploadCAS(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.digi:
        return _uploadDIGI(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.rongta:
        return _uploadRongta(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.aclas:
        return _uploadAclas(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.mettlerToledo:
        return _uploadMettlerToledo(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.tem:
        return _uploadTEM(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.dibal:
        return _uploadDibal(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
      case LabelScaleBrand.nvkTma:
        return _uploadNVK(items, connection, ip, port, com, baud, dataBits, parity, stopBits);
    }
  }
}
