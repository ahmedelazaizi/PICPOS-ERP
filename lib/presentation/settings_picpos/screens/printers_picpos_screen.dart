import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../screens/printers_screen.dart' show PrintersBody;

/// إدارةُ الطابعات بترويسة PicPos الموحّدة (`HEADS.printers`).
///
/// **قشرةٌ لا نسخة**: المنطقُ كلُّه في `PrintersBody`، وتركبه قشرةُ UralCash
/// في ملفّها كما هي. زرُّ «طابعة جديدة» في الترويسة يبلغ الجسمَ عبر
/// [PicPosBodyHandle].
class PrintersPicposScreen extends StatefulWidget {
  const PrintersPicposScreen({super.key});

  @override
  State<PrintersPicposScreen> createState() => _PrintersPicposScreenState();
}

class _PrintersPicposScreenState extends State<PrintersPicposScreen> {
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
      title: 'إدارة الطابعات',
      subtitle: 'الإعدادات ← الأجهزة والطباعة',
      icon: PhosphorIconsBold.printer,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'بحث باسم الطابعة...',
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
            label: const Text('طابعة جديدة'),
          ),
        ),
      ],
      bodyPadding: EdgeInsets.zero,
      body: PrintersBody(addHandle: _addHandle, searchQuery: _query),
    );
  }
}
