import 'package:ural_erp/core/i18n/tr.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// K-3 — «الموقع»: opens the van GPS stamp of a field document / visit in
/// Google Maps. Renders nothing while [url] is null (no fix captured).
class FieldGeoLink extends StatelessWidget {
  const FieldGeoLink({super.key, required this.url, this.dense = true});

  final String? url;
  final bool dense;

  /// The link once [url] resolves (e.g. a raw-column lookup).
  static Widget future(Future<String?> url) => FutureBuilder<String?>(
        future: url,
        builder: (context, snap) => FieldGeoLink(url: snap.data),
      );

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return const SizedBox.shrink();
    return TextButton.icon(
      style: dense
          ? TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            )
          : null,
      onPressed: () =>
          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
      icon: const Icon(Icons.location_on_outlined, size: 16),
      label: Text(tr('الموقع')),
    );
  }
}
