import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/cfd_service.dart';
import '../../picpos_shell/picpos_surface.dart';

/// INT-09 — the owner's opt-in for re-connecting the saved customer display
/// (serial / USB / HDMI) when the app starts.
///
/// Off by default: re-connecting can open a COM port or launch a browser
/// window on its own at every start, so it happens only after the owner turns
/// this on. The display settings themselves always load at start
/// ([CfdService.restoreAtStartup]); this switch only governs the connection.
class CfdAutoConnectSwitch extends StatefulWidget {
  const CfdAutoConnectSwitch({super.key, CfdService? service})
      : _service = service;

  final CfdService? _service;

  @override
  State<CfdAutoConnectSwitch> createState() => _CfdAutoConnectSwitchState();
}

class _CfdAutoConnectSwitchState extends State<CfdAutoConnectSwitch> {
  CfdService get _cfd => widget._service ?? CfdService.instance;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        tr('إعادة الاتصال بشاشة العميل تلقائياً عند التشغيل'),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(
        tr('عند التفعيل يفتح البرنامج منفذ COM أو نافذة المتصفح للشاشة المحفوظة عند كل تشغيل. معطّل افتراضياً.'),
        style: TextStyle(fontSize: 11, color: context.picposMuted),
      ),
      value: _cfd.autoConnectOnStartup,
      activeTrackColor: AppColors.primary,
      onChanged: (v) async {
        await _cfd.setAutoConnectOnStartup(v);
        if (mounted) setState(() {});
      },
    );
  }
}
