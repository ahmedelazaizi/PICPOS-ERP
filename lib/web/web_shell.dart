// غلاف التنقّل للويب (م3-8): شريطٌ جانبيٌّ عربيٌّ (RTL) مبنيٌّ من الشاشات
// المسموحة للمستخدم، ومنطقُ محتوى يعرض الشاشة المختارة.
//
// * الشاشات = [kWebScreenIds] ∩ نطاق البروفايل (`AppConfig.allowedScreenIds`)
//   ∩ صلاحيات الجلسة (`WebSession.permissionCodes`؛ مدير النظام يتجاوز).
// * شاشةٌ مشمولةٌ بلا باني في [kWebScreenBuilders] تُعرض «قريبًا» (لا استيراد).
// * مداخلُ التنقّل وأيقوناتُها ورؤوسُ مجموعاتها من `kAllNavItemDefs` /
//   `kNavGroupDefs` نفسِها — لا قائمةٌ موازية.
//
// * `SecurityScreenGate` (كلمات مرور الأقسام: `*_access_password`) **لا تُضمَّن**
//   هنا عمداً (م3-9): (١) البوّابة مقارنةٌ نصّيّة في العميل بقيمةٍ تُقرأ من جدول
//   `settings`، وقناةُ /webdb تُفرِّغ قيمَ مفاتيح الإعدادات التي تحوي
//   `password|secret|token…` (`WebReadPolicyInterceptor`) — فتقرأها البوّابةُ فارغةً
//   وتفتح دائماً، أي واجهةٌ مضلِّلةٌ بلا حماية؛ (٢) تضمينُها بإفشاء الكلمة للمتصفح
//   تسريبٌ أسوأ من غيابها. الأمان الفعلي على الخادم: صلاحياتُ المستخدم تُفحص في
//   كلّ معالج (`ApiUserCtx`) وفي سياسة القراءة (دورٌ ← جداول)، ومداخلُ هذا الغلاف
//   مقطوعةٌ بصلاحيات الجلسة. (قفلُ الأقسام بكلمة مرور = راحةُ كاشير على الديسكتوب.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/navigation/screen_id.dart';
import '../data/providers/auth_providers.dart'
    show NavGroupDef, NavItemDef, kAllNavItemDefs, kNavGroupDefs;
import 'web_providers.dart';
import 'web_screen_registry.dart';
import 'web_screen_scope.dart';
import 'web_session.dart';

/// علامةُ تجاوز المدير في أكواد المستخدم (`PermissionsDao.getUserPermissionCodes`).
const String kWebSystemAdminCode = 'system_admin';

/// هل [session] مدير نظامٍ يتجاوز فحص الصلاحيات؟ (نفس اقتران `_isAdminRole`:
/// دورٌ مدمجٌ باسم «مدير النظام».)
bool webSessionIsSystemAdmin(WebSession session) =>
    session.permissionCodes.contains(kWebSystemAdminCode) ||
    (session.roleIsSystem && session.roleName == 'مدير النظام');

/// فهارس التنقّل المسموحة على الويب لنطاقٍ [allowed] (الافتراضي: نطاق
/// البروفايل الحاليّ مقطوعاً بـ[kWebScreenIds]).
Set<int> webAllowedNavIndexes([Iterable<ScreenId>? allowed]) => {
      for (final s in allowed ?? AppConfig.allowedScreenIds)
        if (kWebScreenIds.contains(s)) s.navigationIndex,
    };

/// مداخلُ القائمة الجانبية للمستخدم: مشمولةٌ في الويب + ضمن النطاق + مصرَّحٌ بها.
///
/// دالّةٌ خالصة (بلا Riverpod/قاعدة) ليقيسها الاختبار.
List<NavItemDef> webNavItemsFor(
  WebSession session, {
  Iterable<ScreenId>? allowed,
}) {
  final indexes = webAllowedNavIndexes(allowed);
  final bypass = webSessionIsSystemAdmin(session);
  final codes = session.permissionCodes.toSet();
  return [
    for (final item in kAllNavItemDefs)
      if (indexes.contains(item.index) &&
          (item.permission == null ||
              bypass ||
              codes.contains(item.permission)))
        item,
  ];
}

/// شاشةُ «قريبًا» لما هو مشمولٌ ولم يُترجَم بعد.
class WebComingSoon extends StatelessWidget {
  const WebComingSoon({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_outlined,
              size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('قريبًا في نسخة الويب', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class WebShell extends ConsumerStatefulWidget {
  const WebShell({super.key, required this.session});

  final WebSession session;

  @override
  ConsumerState<WebShell> createState() => _WebShellState();
}

class _WebShellState extends ConsumerState<WebShell> {
  late final List<NavItemDef> _items = webNavItemsFor(widget.session);
  int? _index;

  @override
  void initState() {
    super.initState();
    if (_items.isNotEmpty) {
      _index = _items
          .firstWhere((i) => i.index == ScreenId.dashboard.navigationIndex,
              orElse: () => _items.first)
          .index;
    }
  }

  void _go(int index) {
    if (_items.any((i) => i.index == index)) {
      setState(() => _index = index);
    }
  }

  void _signOut() {
    ref.invalidate(webConnectionProvider);
    ref.read(webSessionProvider.notifier).signOut();
  }

  Widget _content() {
    final index = _index;
    if (index == null) {
      return const WebComingSoon(title: 'لا توجد شاشات مسموحة لهذا المستخدم');
    }
    final item = _items.firstWhere((i) => i.index == index);
    final id = ScreenId.fromIndex(index);
    final builder = id == null ? null : kWebScreenBuilders[id];
    return KeyedSubtree(
      key: ValueKey(index),
      child: builder == null
          ? WebComingSoon(title: item.label)
          : builder(_go),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lost = ref.watch(webConnectionProvider);
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebar = _Sidebar(items: _items, selected: _index, onSelect: (i) {
      _go(i);
      if (!wide) Navigator.of(context).maybePop();
    });
    return Scaffold(
      appBar: AppBar(
        title: Text('PicPos Web — ${widget.session.displayName}'),
        actions: [
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('خروج'),
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: sidebar),
      body: Column(
        children: [
          if (lost != null)
            MaterialBanner(
              backgroundColor: theme.colorScheme.errorContainer,
              content: Text(lost),
              actions: [
                TextButton(
                  onPressed: _signOut,
                  child: const Text('تسجيل الدخول'),
                ),
              ],
            ),
          Expanded(
            child: Row(
              children: [
                if (wide) SizedBox(width: 260, child: sidebar),
                if (wide) const VerticalDivider(width: 1),
                Expanded(child: _content()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// الشريط الجانبي: مداخلُ [items] مجمَّعةً برؤوس `kNavGroupDefs` بترتيب أوّل ظهور.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<NavItemDef> items;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = <String>[];
    final byGroup = <String, List<NavItemDef>>{};
    for (final i in items) {
      final g = i.group ?? 'other';
      if (!byGroup.containsKey(g)) order.add(g);
      byGroup.putIfAbsent(g, () => []).add(i);
    }
    final meta = {for (final NavGroupDef g in kNavGroupDefs) g.key: g};
    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final g in order) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                meta[g]?.label ?? g,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            for (final i in byGroup[g]!)
              ListTile(
                dense: true,
                selected: i.index == selected,
                leading: Icon(i.icon, size: 20),
                title: Text(i.label),
                onTap: () => onSelect(i.index),
              ),
          ],
        ],
      ),
    );
  }
}
