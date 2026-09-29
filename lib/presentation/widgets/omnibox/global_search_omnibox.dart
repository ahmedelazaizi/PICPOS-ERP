import 'package:ural_erp/core/i18n/tr.dart';
import '../../../core/navigation/screen_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
// To access _navigateToScreen indirectly or via a provider

class GlobalSearchOmnibox extends ConsumerStatefulWidget {
  final Widget child;
  final Function(int) onNavigateToScreen;

  const GlobalSearchOmnibox({
    super.key,
    required this.child,
    required this.onNavigateToScreen,
  });

  @override
  ConsumerState<GlobalSearchOmnibox> createState() => _GlobalSearchOmniboxState();
}

class _GlobalSearchOmniboxState extends ConsumerState<GlobalSearchOmnibox> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Keep focus so shortcuts always work if nothing else is focused.
    // However, FocusableActionDetector doesn't need to be exclusively focused if we use a global shortcut approach,
    // but the best way is wrapping the whole app body in Shortcuts.
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _showSearchDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Omnibox',
      pageBuilder: (context, animation, secondaryAnimation) {
        return _SearchOverlay(onNavigateToScreen: widget.onNavigateToScreen);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK): const _SearchIntent(),
        // Also support CMD+K for Mac
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK): const _SearchIntent(),
      },
      child: Actions(
        actions: {
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (intent) {
              _showSearchDialog();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _SearchOverlay extends ConsumerStatefulWidget {
  final Function(int) onNavigateToScreen;

  const _SearchOverlay({required this.onNavigateToScreen});

  @override
  ConsumerState<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<_SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _searchFocus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    
    // Quick static search for screens (can be expanded via GlobalSearchService later)
    final allScreens = [
      {'title': 'Dashboard', 'screenIndex': 0, 'icon': PhosphorIconsBold.house},
      {'title': tr('البيع السريع (الكاشير)'), 'screenIndex': 1, 'icon': PhosphorIconsBold.shoppingCart},
      {'title': tr('إدارة المبيعات والفواتير'), 'screenIndex': 16, 'icon': PhosphorIconsBold.fileText},
      {'title': tr('المشتريات'), 'screenIndex': 8, 'icon': PhosphorIconsBold.receipt},
      {'title': tr('المخازن والمستودعات'), 'screenIndex': 7, 'icon': PhosphorIconsBold.warehouse},
      {'title': tr('الخزينة والمالية'), 'screenIndex': 9, 'icon': PhosphorIconsBold.wallet},
      {'title': tr('دليل العملاء والموردين'), 'screenIndex': 6, 'icon': PhosphorIconsBold.usersThree},
      {'title': tr('الأصناف والمنتجات'), 'screenIndex': 4, 'icon': PhosphorIconsBold.package},
      {'title': tr('الإعدادات'), 'screenIndex': 11, 'icon': PhosphorIconsBold.gear},
      // 🔴 **كان `31` — وهو «ربط الحسابات».** فمن يبحث عن اليومية في
      // البحث الشامل كان يُفتَح له ربطُ الحسابات. والفهرسُ يُقرأ من
      // `ScreenId` لا يُكتَب رقماً، فالفئةُ كلُّها تسقط.
      {
        'title': journalEntriesScreenLabel,
        'screenIndex': ScreenId.journalEntries.navigationIndex,
        'icon': PhosphorIconsBold.notebook,
      },
      {'title': tr('التقارير'), 'screenIndex': 10, 'icon': PhosphorIconsBold.chartBar},
      {'title': tr('إدارة الفروع'), 'screenIndex': 12, 'icon': PhosphorIconsBold.buildings},
    ];

    final matchingScreens = allScreens.where((s) => (s['title'] as String).toLowerCase().contains(lowerQuery)).toList();

    setState(() {
      _results = [
        ...matchingScreens.map((s) => {
          ...s,
          'type': tr('شاشةระบบ'),
        }),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.5),
      body: Center(
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _controller,
                  focusNode: _searchFocus,
                  autofocus: true,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    hintText: tr('ابحث عن شاشة، فاتورة، عميل، صنف... (Esc للإغلاق)'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  onChanged: _performSearch,
                  onSubmitted: (_) {
                    if (_results.isNotEmpty) {
                      _navigate(_results.first);
                    }
                  },
                ),
              ),
              if (_results.isNotEmpty)
                const Divider(height: 1),
              if (_results.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final res = _results[index];
                      return ListTile(
                        leading: Icon(res['icon'] as IconData, color: Theme.of(context).primaryColor),
                        title: Text(res['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(res['type'] as String),
                        onTap: () => _navigate(res),
                      );
                    },
                  ),
                ),
              if (_results.isEmpty && _controller.text.isNotEmpty)
                 Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(tr('لا توجد نتائج مطابقة'), style: const TextStyle(color: Colors.grey)),
                )
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(Map<String, dynamic> result) {
    Navigator.pop(context);
    widget.onNavigateToScreen(result['screenIndex'] as int);
  }
}
