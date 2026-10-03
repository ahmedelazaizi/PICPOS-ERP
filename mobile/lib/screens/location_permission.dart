import 'package:flutter/material.dart';

import '../geo/geo_capture.dart';
import '../l10n/strings.dart';
import '../state/app_controller.dart';

/// K-3 — asks for location at the right moment (when the rep opens his
/// route), after an in-app rationale (AR/EN), at most once a day. A refusal
/// is respected: documents are then saved without GPS and marked so.
Future<void> askLocationIfNeeded(BuildContext context, AppController c, {DateTime Function()? clock}) async {
  final geo = c.geo;
  if (geo == null) return;
  final provider = geo.provider;
  if (await provider.permission() != GeoPermission.denied) return;
  final now = (clock ?? DateTime.now)();
  final today = '${now.year}-${now.month}-${now.day}';
  if (await c.store.getKv('geoRationaleDay') == today) return;
  await c.store.setKv('geoRationaleDay', today);
  if (!context.mounted) return;
  final s = S.of(context);
  final allow = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_on_outlined),
      title: Text(s.t('locationTitle')),
      content: Text(s.t('locationRationale')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('notNow'))),
        FilledButton(
            key: const Key('allowLocation'), onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('allow'))),
      ],
    ),
  );
  if (allow == true) await provider.request();
}
