import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../screens/settings/work_holidays_screen.dart' show WorkHolidaysBody;

/// العطلاتُ وأيّامُ العمل بترويسة PicPos الموحّدة (`HEADS.holidays`).
///
/// **قشرةٌ لا نسخة**: المنطقُ كلُّه في `WorkHolidaysBody`، وتركبه قشرةُ
/// UralCash في ملفّها كما هي. زرُّ «عطلة جديدة» في الترويسة يبلغ الجسمَ عبر
/// [PicPosBodyHandle] — انظر توثيقَها لسببِ كونِ الجاهزيّةِ مُستمَعاً إليها.
class WorkHolidaysPicposScreen extends StatefulWidget {
  const WorkHolidaysPicposScreen({super.key});

  @override
  State<WorkHolidaysPicposScreen> createState() =>
      _WorkHolidaysPicposScreenState();
}

class _WorkHolidaysPicposScreenState extends State<WorkHolidaysPicposScreen> {
  final _searchCtrl = TextEditingController();
  final _addHandle = PicPosBodyHandle();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _addHandle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('العطلات وأيام العمل'),
      subtitle: tr('الإعدادات ← النظام والمظهر'),
      icon: PhosphorIconsBold.calendar,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('بحث عن عطلة...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
        ),
      ),
      headerActions: [
        ValueListenableBuilder<bool>(
          valueListenable: _addHandle.isReady,
          builder: (_, ready, _) => ElevatedButton.icon(
            onPressed: ready ? _addHandle.invoke : null,
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label:  Text(tr('عطلة جديدة')),
          ),
        ),
      ],
      bodyPadding: EdgeInsets.zero,
      body: WorkHolidaysBody(addHandle: _addHandle, searchQuery: _query),
    );
  }
}
