import 'package:ural_erp/core/i18n/tr.dart';
// مصفوفةُ الأدوار والصلاحيات — نسخةُ PicPos المستقلّة.
//
// المصدر: `BENCH.perms` في «PicPos Settings.dc.html» (‏المشروع
// 2c7b6006-4708-4883-95b7-59612cd6b517). التصميمُ يرسم **منضدةَ عمل**
// عرضُها ١٤٨٠: الأدوارُ أعمدةٌ والصلاحياتُ صفوفٌ، والتبديلُ في مكانه،
// ولوحةٌ يمينَ العرض تجمع «التعديلات غير المحفوظة» ثمّ تُحفَظ دفعةً.
//
// ═══ لماذا نسخةٌ لا تعديلٌ على المشترك ═══
//
// أمرُ المالك 2026-08-25: «لا تربط أيَّ أمورٍ من UralCash. إذا كان هناك أمرٌ
// مشتركٌ ولا نريد أن نعدّل على UralCash فقم بنسخه إلى PicPos بشكلٍ منفصل».
// و`PermissionsManagementWidget` المشتركةُ تبقى كما هي لمسار UralCash
// (‏`settings_screen.dart`)، وهذه تخدم مسارَ PicPos وحدَه.
//
// ═══ الحالاتُ الثلاث — والثالثةُ بُنيت بأمر المالك ═══
//
// الخليّةُ ثلاثيّةٌ كما في التصميم: مسموح (‏✓ أخضر) · مشروط (‏− كهرمانيّ) ·
// ممنوع (‏✕ رماديّ). ودورتُها ترتيبُ الشِّدّة: ممنوع ← مسموح ← مشروط.
//
// وكان `RolePermissions` **جدولَ وجودٍ لا حالة** (‏صفٌّ = ممنوح، وغيابُه =
// ممنوع)، فرُفض رسمُ خليّةٍ كهرمانيّةٍ تُحفَظ «ممنوحة» — كذبٌ أمنيّ. ثمّ أمر
// المالكُ ببنائها 2026-08-25، فأُضيف `grant_mode` (‏هجرة v163).
//
// **و«مشروط» = ممنوحةٌ ويمرّ تنفيذُها بموافقة مسؤولٍ في كلّ مرّة.** ولم
// تُبنَ لها آليّةٌ جديدة: `ensurePermission` تملك مسارَ `requestManagerApproval`
// منذ اليوم، والمشروطُ يمنعها من الاختصار عند فحص المِلك فتنزل إليه.
//
// ═══ ما نُقل من التصميم بمقياسٍ من الشجرة ═══
//
// • مثلَّثُ الخطر على الصفّ = `PermissionCodes.criticalFinancialOps` — وهو
//   مفهومٌ **قائمٌ ومنفَّذ**: تلك الأكواد لا تُمنَح للمدير تلقائيّاً
//   (‏`database_seeder_permissions.dart`) ولا يتخطّاها تجاوزُ المدير في
//   `permission_guard.dart`. وهذا عينُ ما يقوله نصُّ التصميم: «تُفحَص على
//   السيرفر ولا يمكن تجاوزها محلياً».
//
// • الأكوادُ غيرُ القابلة للتبديل (`PermissionCodes.nonToggleable`) **مستبعدةٌ**
//   من المصفوفة — كما تُخفيها الشاشةُ المشتركةُ افتراضيّاً. سببُ الإخفاء
//   موثَّقٌ هناك: بلاغُ «بغيّر صلاحية ومفيش حاجة بتحصل»، فلا مستقبِلَ لقرارها.
//   وعرضُها في مصفوفةٍ يجعل العطبَ أعرضَ لا أضيق.
//
// • كلُّ عددٍ في الشاشة مشتقٌّ من الشجرة: عددُ الأدوار وعددُ الصلاحيات وعدّادُ
//   كلِّ دورٍ وعدّادُ كلِّ مجموعةٍ وعددُ المعلَّق. لا رقمَ مكتوباً بجانب ما يعدّه.
//
// ⚠️ **وعددُ الأعمدة ليس ستّةً كما في التصميم.** المزروعُ تسعةُ أدوارٍ
// (‏`RoleGrantMatrix.defaultGrants`) وقد يضيف المشغّلُ غيرَها، فالأعمدةُ
// تُبنى من القاعدة ويُمرَّر الجدولُ أفقيّاً حين تضيق — لا عرضٌ ثابتٌ لستّة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';

/// يفتح منضدةَ «مصفوفة الأدوار والصلاحيات».
void showPermissionsMatrixPicpos(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _PermissionsMatrixDialog(),
  );
}

class _PermissionsMatrixDialog extends ConsumerStatefulWidget {
  const _PermissionsMatrixDialog();

  @override
  ConsumerState<_PermissionsMatrixDialog> createState() =>
      _PermissionsMatrixDialogState();
}

/// مجموعةُ صفوفٍ في المصفوفة — فئةُ صلاحياتٍ واحدة.
class _MatrixGroup {
  _MatrixGroup(this.category, this.perms);

  final String category;
  final List<Permission> perms;

  String get label => PermissionCodes.categoryNames[category] ?? category;
}

/// حالةُ الخليّة الثلاثيّة — حالاتُ التصميم نفسُها بترتيبها.
enum _Grant {
  /// ✕ رماديّ — لا صفَّ في `role_permissions`.
  denied,

  /// ✓ أخضر — صفٌّ بنمط `allow`.
  allowed,

  /// − كهرمانيّ — صفٌّ بنمط `conditional`: ممنوحةٌ ويمرّ تنفيذُها بموافقة
  /// مسؤولٍ في كلّ مرّة.
  conditional,
}

/// تعديلٌ معلَّقٌ واحد — ما تعرضه لوحةُ «التعديلات غير المحفوظة».
class _PendingChange {
  const _PendingChange({
    required this.to,
    required this.roleName,
    required this.permName,
    required this.risky,
  });

  final _Grant to;
  final String roleName;
  final String permName;
  final bool risky;
}

class _PermissionsMatrixDialogState
    extends ConsumerState<_PermissionsMatrixDialog> {
  static const double _labelW = 236;
  static const double _cellW = 96;
  static const double _sideW = 340;
  static const double _rowH = 44;

  List<Role> _roles = const [];
  List<_MatrixGroup> _groups = const [];

  /// خطُّ الأساس المحمَّل من القاعدة: الدور → الصلاحية → حالتُها.
  ///
  /// الغائبُ من الخريطة الداخليّة ممنوعٌ — فلا تُخزَّن حالاتُ المنع.
  final Map<int, Map<int, _Grant>> _baseline = {};

  /// المعلَّق: `roleId:permId` → الحالةُ المطلوبة. لا يحوي إلّا ما يخالف
  /// خطَّ الأساس — فالضغطةُ التي تُعيد الخليّةَ لأصلها **تحذف** المفتاح.
  final Map<String, _Grant> _pending = {};

  bool _loading = true;
  bool _saving = false;

  static String _key(int roleId, int permId) => '$roleId:$permId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final roles = await repo.getAllRoles();
      final perms = await repo.getAllPermissions();

      // ⚠️ استعلامٌ لكلّ دور — تسعةُ استعلاماتٍ عند الفتح. مقبولٌ لأنّه يقع
      //    مرّةً واحدةً عند فتح الحوار لا في كلّ إطار، ولا واجهةَ دفعةٍ في
      //    المستودع تقرأ صلاحياتِ كلِّ الأدوار معاً.
      _baseline.clear();
      for (final r in roles) {
        final modes = await repo.getRolePermissionModes(r.id);
        _baseline[r.id] = {
          for (final e in modes.entries)
            e.key: e.value == PermissionCodes.grantConditional
                ? _Grant.conditional
                : _Grant.allowed,
        };
      }

      final toggleable = perms
          .where((p) => !PermissionCodes.nonToggleable.containsKey(p.code))
          .toList();

      final byCat = <String, List<Permission>>{};
      for (final p in toggleable) {
        byCat.putIfAbsent(p.category, () => []).add(p);
      }

      // الترتيبُ ترتيبُ `categoryNames` نفسِه (‏خريطةٌ حرفيّةٌ فترتيبُها
      // ترتيبُ الإدراج)، وما ليس فيها يُلحَق آخراً بترتيبٍ أبجديّ.
      final known = PermissionCodes.categoryNames.keys
          .where(byCat.containsKey)
          .toList();
      final unknown = byCat.keys
          .where((c) => !PermissionCodes.categoryNames.containsKey(c))
          .toList()
        ..sort();

      _roles = roles;
      _groups = [
        for (final c in [...known, ...unknown]) _MatrixGroup(c, byCat[c]!),
      ];
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر تحميل المصفوفة: {e}', {'e': e}),
            type: ToastType.error);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  _Grant _grantOf(int roleId, int permId) =>
      _pending[_key(roleId, permId)] ??
      _baseline[roleId]?[permId] ??
      _Grant.denied;

  /// دورةُ الحالات: ممنوع ← مسموح ← مشروط ← ممنوع.
  ///
  /// وترتيبُها ترتيبُ الشِّدّة: الضغطةُ الأولى تمنح، والثانيةُ تُقيّد المنحَ
  /// بموافقةٍ، والثالثةُ تسحب. فمن يضغط مرّةً لا يقع على «مشروط» بغير قصد.
  void _toggle(int roleId, int permId) {
    if (_saving) return;
    final k = _key(roleId, permId);
    final base = _baseline[roleId]?[permId] ?? _Grant.denied;
    const cycle = [_Grant.denied, _Grant.allowed, _Grant.conditional];
    final next = cycle[(cycle.indexOf(_grantOf(roleId, permId)) + 1) % 3];
    setState(() {
      if (next == base) {
        _pending.remove(k);
      } else {
        _pending[k] = next;
      }
    });
  }

  /// عددُ الصلاحيات الممنوحةِ لدورٍ الآن — خطُّ الأساس معدَّلاً بالمعلَّق.
  ///
  /// ⚠️ **يُحسَب على صلاحيات المصفوفة وحدَها.** فخطُّ الأساس يحوي أيضاً
  /// أكواداً غيرَ قابلةٍ للتبديل، وعدُّها هنا يعطي رقماً لا يطابق ما يراه
  /// المشغّلُ في العمود.
  int _roleCount(int roleId) {
    var n = 0;
    for (final g in _groups) {
      for (final p in g.perms) {
        if (_grantOf(roleId, p.id) != _Grant.denied) n++;
      }
    }
    return n;
  }

  int get _permCount =>
      _groups.fold<int>(0, (sum, g) => sum + g.perms.length);

  List<_PendingChange> get _changes {
    final out = <_PendingChange>[];
    for (final e in _pending.entries) {
      final parts = e.key.split(':');
      final roleId = int.parse(parts.first);
      final permId = int.parse(parts.last);
      final role = _roles.where((r) => r.id == roleId).firstOrNull;
      Permission? perm;
      for (final g in _groups) {
        perm = g.perms.where((p) => p.id == permId).firstOrNull;
        if (perm != null) break;
      }
      if (role == null || perm == null) continue;
      out.add(_PendingChange(
        to: e.value,
        roleName: role.name,
        permName: perm.name,
        risky: PermissionCodes.criticalFinancialOps.contains(perm.code),
      ));
    }
    out.sort((a, b) => a.roleName.compareTo(b.roleName));
    return out;
  }

  Future<void> _save() async {
    if (_pending.isEmpty || _saving) return;
    setState(() => _saving = true);

    // الحفظُ بالدور: `setRolePermissions` تكتب مجموعةَ الدور كاملةً، فتُجمَع
    // تعديلاتُ الدور الواحد في نداءٍ واحدٍ بدل نداءٍ لكلّ خليّة.
    final touched = <int>{};
    for (final k in _pending.keys) {
      touched.add(int.parse(k.split(':').first));
    }

    final repo = ref.read(authRepositoryProvider);
    final failed = <String>[];
    var saved = 0;

    for (final roleId in touched) {
      final next = {...?_baseline[roleId]};
      for (final e in _pending.entries) {
        final parts = e.key.split(':');
        if (int.parse(parts.first) != roleId) continue;
        final permId = int.parse(parts.last);
        if (e.value == _Grant.denied) {
          next.remove(permId);
        } else {
          next[permId] = e.value;
        }
      }
      try {
        // ⚠️ **المعرِّفاتُ والأنماطُ من نفس الخريطة** — فلا يقع أن تُكتَب
        //    صلاحيةٌ ممنوحةً بنمطٍ يخصُّ غيرَها، ولا أن يُمنَح صفٌّ بلا نمط.
        await repo.setRolePermissions(
          roleId,
          next.keys.toList(),
          modes: {
            for (final e in next.entries)
              e.key: e.value == _Grant.conditional
                  ? PermissionCodes.grantConditional
                  : PermissionCodes.grantAllow,
          },
        );
        _baseline[roleId] = next;
        ref.invalidate(rolePermissionsProvider(roleId));
        saved++;
      } catch (e) {
        final name =
            _roles.where((r) => r.id == roleId).firstOrNull?.name ?? '$roleId';
        failed.add(name);
      }
    }

    ref.invalidate(currentUserPermissionsProvider);

    // ⚠️ لا تُمسَح إلّا تعديلاتُ الأدوار التي نجحت — مسحُ الكلّ بعد فشلٍ
    //    جزئيٍّ يُخفي ما لم يُحفَظ ويترك المشغّلَ يظنّه محفوظاً.
    setState(() {
      _pending.removeWhere((k, _) {
        final roleId = int.parse(k.split(':').first);
        final name =
            _roles.where((r) => r.id == roleId).firstOrNull?.name ?? '$roleId';
        return !failed.contains(name);
      });
      _saving = false;
    });

    if (!mounted) return;
    if (failed.isEmpty) {
      AppToast.show(context, tr('✓ حُفظت المصفوفة — {saved} دور', {'saved': saved}), type: ToastType.success);
      Navigator.of(context).maybePop();
    } else {
      AppToast.show(
        context,
        tr('تعذّر حفظ {p0} دور: {p1}', {'p0': failed.length, 'p1': failed.join("، ")}),
        type: ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending.length;

    return PicPosDialog(
      icon: PhosphorIconsBold.table,
      title: tr('مصفوفة الأدوار والصلاحيات'),
      subtitle: tr('قارن الأدوار جنباً إلى جنب وبدّل الصلاحية في مكانها بدلاً من فتح كل دور على حدة'),
      width: 1480,
      scrollable: false,
      bodyFill: true,
      headerChips: [
        if (pending > 0)
          PicPosDialogChip(
            icon: PhosphorIconsBold.pencilSimple,
            label: tr('{pending} تعديل غير محفوظ', {'pending': pending}),
            tint: AppColors.warning,
          ),
      ],
      footerHint: _loading
          ? tr('جارٍ تحميل الأدوار والصلاحيات…')
          : tr('{p0} دور · {_permCount} صلاحية · {pending} تعديل معلّق', {'p0': _roles.length, '_permCount': _permCount, 'pending': pending}),
      onCancel: () => Navigator.of(context).maybePop(),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ المصفوفة'),
        icon: PhosphorIconsBold.check,
        busy: _saving,
        onPressed: pending == 0 || _saving ? null : _save,
      ),
      // ⚠️ **الارتفاعُ مقيسٌ من القيد لا مُقدَّرٌ من ارتفاع الشاشة.** أوّلُ
      // كتابةٍ حسبته `screenHeight - 220` فطفح الجسمُ ٧ بكسل: الرأسُ
      // والتذييلُ أطولُ من التقدير، والفيضُ شريطٌ أصفرُ وأسودُ فوق الواجهة.
      // و`PicPosDialog` يضع الجسمَ في `Flexible` فيصل هنا **أقصى المتاح
      // فعلاً** — فيُؤخَذ كما هو ولا يُخمَّن. والاحتياطُ للانهائيّ فقط.
      body: [
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: c.maxHeight.isFinite ? c.maxHeight : 640,
            child: _content(context),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_roles.isEmpty || _groups.isEmpty) {
      return Center(
        child: Text(
          tr('لا أدوارَ أو صلاحياتٍ لعرضها'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.picposMuted,
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _matrixCard(context)),
        const SizedBox(width: 16),
        SizedBox(width: _sideW, child: _sidePanel(context)),
      ],
    );
  }

  // ── المصفوفة ───────────────────────────────────────────────────────────

  Widget _matrixCard(BuildContext context) {
    final totalW = _labelW + _cellW * _roles.length;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          // ⚠️ **تمريرٌ أفقيٌّ واحدٌ يلفّ الترويسةَ والصفوفَ معاً** — لو وُضع
          //    لكلٍّ منهما تمريرُه لانزلق رأسُ العمود عن خليّته. والترويسةُ
          //    خارجَ التمرير الرأسيّ فتبقى ثابتةً كما في التصميم
          //    (`position:sticky;top:0`).
          final w = totalW < box.maxWidth ? box.maxWidth : totalW;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _headerRow(context),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final g in _groups) ...[
                            _groupRow(context, g),
                            for (final p in g.perms) _permRow(context, p),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// ⚠️ **`IntrinsicHeight` لازمةٌ هنا لا زينة.** الترويسةُ ليست في `Expanded`
  /// فارتفاعُها غيرُ محدود، و`CrossAxisAlignment.stretch` في ارتفاعٍ غيرِ
  /// محدودٍ تُجبر الأبناءَ على `infinity` فينهار التخطيط. والـstretch مطلوبةٌ
  /// كي يمتدّ فاصلُ العمود بكامل ارتفاع الرأس كما في التصميم — فالحلُّ حدُّ
  /// الارتفاع لا إسقاطُ الفاصل. وهي ودجتٌ **واحدةٌ** لا واحدةٌ لكلّ صفّ.
  Widget _headerRow(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _labelW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  tr('الصلاحية'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposMuted,
                  ),
                ),
              ),
            ),
          ),
          for (final r in _roles)
            Expanded(child: _roleHead(context, r)),
        ],
        ),
      ),
    );
  }

  Widget _roleHead(BuildContext context, Role r) {
    final tint = _roleTint(r.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: context.picposHairline),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(r.name), size: 16, color: tint),
          const SizedBox(height: 4),
          Text(
            r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_roleCount(r.id)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupRow(BuildContext context, _MatrixGroup g) {
    final tint = _categoryTint(g.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .07),
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Icon(_categoryIcon(g.category), size: 16, color: tint),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              g.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
          ),
          Text(
            tr('{p0} صلاحية', {'p0': g.perms.length}),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ **ارتفاعٌ ثابتٌ لا `IntrinsicHeight`.** الصفُّ يحتاج الـstretch كي
  /// يمتدّ فاصلُ العمود بكامل ارتفاعه، والـstretch تحتاج ارتفاعاً محدوداً —
  /// والصفوفُ **مئاتٌ** (‏٢٩ فئةً × صلاحياتها)، فـ`IntrinsicHeight` لكلٍّ
  /// منها قياسٌ مضاعفٌ في كلّ إطار. و[_rowH] هو ارتفاعُ الخليّة نفسِها
  /// (‏٩ + ٢٦ + ٩) وهي أطولُ من عنوان الصفّ، فلا يُقتطع نصّ.
  Widget _permRow(BuildContext context, Permission p) {
    final risky = PermissionCodes.criticalFinancialOps.contains(p.code);
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _labelW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.picposText,
                      ),
                    ),
                  ),
                  if (risky) ...[
                    const SizedBox(width: 7),
                     Tooltip(
                      message: tr('صلاحيةٌ ماليّةٌ حرجة — تُفحَص على الخادم ولا يتخطّاها تجاوزُ المدير'),
                      child: const Icon(
                        PhosphorIconsBold.warning,
                        size: 13,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          for (final r in _roles)
            Expanded(child: _cell(context, r.id, p.id)),
        ],
      ),
    );
  }

  /// ألوانُ الحالة الثلاث — نفسُ ترميز التصميم حرفيّاً.
  static ({IconData icon, Color box, Color fg, Color wash}) _skin(
    BuildContext context,
    _Grant g,
  ) {
    switch (g) {
      case _Grant.allowed:
        return (
          icon: PhosphorIconsBold.check,
          box: AppColors.success,
          fg: Colors.white,
          wash: AppColors.success.withValues(alpha: .06),
        );
      case _Grant.conditional:
        return (
          icon: PhosphorIconsBold.minus,
          box: AppColors.warning,
          fg: Colors.white,
          wash: AppColors.warning.withValues(alpha: .08),
        );
      case _Grant.denied:
        return (
          icon: PhosphorIconsBold.x,
          box: context.picposField,
          fg: context.picposMuted,
          wash: Colors.transparent,
        );
    }
  }

  Widget _cell(BuildContext context, int roleId, int permId) {
    final g = _grantOf(roleId, permId);
    final s = _skin(context, g);
    final dirty = _pending.containsKey(_key(roleId, permId));
    return Material(
      color: s.wash,
      child: InkWell(
        // مفتاحٌ للخليّة — الجدولُ ثنائيُّ البعد، والوصولُ إليه بـ`ancestor`
        // يلتقط صفَّ العنوان الداخليَّ لا الصفَّ الحامل. والمفتاحُ يقصد
        // خليّةً بعينها بلا التباس.
        key: ValueKey('mx-cell-$roleId-$permId'),
        onTap: () => _toggle(roleId, permId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: context.picposHairline),
            ),
          ),
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: s.box,
                borderRadius: BorderRadius.circular(9),
                // ⚠️ إطارُ «معلَّق» أزرقُ لا كهرمانيّ — الكهرمانيُّ صار لونَ
                //    حالةِ «مشروط» نفسِها، فإطارٌ بنفس اللون يجعل خليّةً
                //    مشروطةً محفوظةً تبدو معلَّقةً وبالعكس.
                border: dirty
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Icon(s.icon, size: 14, color: s.fg),
            ),
          ),
        ),
      ),
    );
  }

  // ── لوحةُ التعديلات ────────────────────────────────────────────────────

  Widget _sidePanel(BuildContext context) {
    final changes = _changes;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: context.picposHairline)),
            ),
            child: Text(
              tr('التعديلات غير المحفوظة'),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: context.picposText,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (changes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        tr('لا تعديلَ بعد — اضغط أيَّ خليّةٍ لتبديل الصلاحية، ويظهر التعديلُ هنا قبل الحفظ.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.7,
                          color: context.picposMuted,
                        ),
                      ),
                    ),
                  for (final c in changes) ...[
                    _changeCard(context, c),
                    const SizedBox(height: 11),
                  ],
                  _noteCard(context),
                ],
              ),
            ),
          ),
          _legend(context),
        ],
      ),
    );
  }

  Widget _changeCard(BuildContext context, _PendingChange c) {
    final tint = switch (c.to) {
      _Grant.allowed => AppColors.success,
      _Grant.conditional => AppColors.warning,
      _Grant.denied => AppColors.error,
    };
    final icon = switch (c.to) {
      _Grant.allowed => PhosphorIconsBold.plusCircle,
      _Grant.conditional => PhosphorIconsBold.shieldWarning,
      _Grant.denied => PhosphorIconsBold.minusCircle,
    };
    // ⚠️ **النصُّ يقول ما سيقع لا «تغيَّر»**: «مشروط» ممنوحةٌ في القاعدة،
    //    فلو قيل «منح» لظنّها المشغّلُ منحاً كاملاً ولم يعلم أنّه اشترط
    //    موافقةً على كلّ تنفيذ.
    final label = switch (c.to) {
      _Grant.allowed => tr('منح «{p0}» لدور {p1}', {'p0': c.permName, 'p1': trData(c.roleName)}),
      _Grant.conditional =>
        tr('جعل «{p0}» مشروطاً لدور {p1} — موافقةُ مسؤولٍ في كلّ مرّة', {'p0': c.permName, 'p1': trData(c.roleName)}),
      _Grant.denied => tr('سحب «{p0}» من دور {p1}', {'p0': c.permName, 'p1': trData(c.roleName)}),
    };
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .06),
        border: Border.all(color: tint.withValues(alpha: .23)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
          if (c.risky) ...[
            const SizedBox(height: 6),
            Text(
              tr('صلاحيةٌ ماليّةٌ حرجة — تُفحَص على الخادم ولا يتخطّاها تجاوزُ المدير.'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.6,
                color: context.picposMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noteCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .07),
        border: Border.all(color: AppColors.warning.withValues(alpha: .30)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(PhosphorIconsBold.warning,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('التغيير يسري على كل مستخدمي الدور عند العملية التالية، والصلاحيات المعلَّمة بمثلث تحذير تُفحَص على الخادم ولا يمكن تجاوزها محلياً.'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.7,
                color: context.picposText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    Widget row(IconData icon, Color box, Color fg, String label) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: box,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 13, color: fg),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposText,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('مفتاح الرموز'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
          row(PhosphorIconsBold.check, AppColors.success, Colors.white,
              tr('مسموح بلا شرط')),
          row(PhosphorIconsBold.minus, AppColors.warning, Colors.white,
              tr('مشروط — موافقةُ مسؤولٍ في كلّ مرّة')),
          row(PhosphorIconsBold.x, context.picposCard, context.picposMuted,
              tr('ممنوع')),
        ],
      ),
    );
  }

  // ── أيقوناتٌ وألوان ────────────────────────────────────────────────────

  /// أيقونةُ الدور — من اسمه، وهو ما تملكه القاعدة. الأسماءُ المزروعةُ
  /// معروفةٌ (`RoleGrantMatrix.defaultGrants`)، وأيُّ دورٍ يضيفه المشغّلُ
  /// يأخذ الأيقونةَ الافتراضيّة.
  IconData _roleIcon(String name) {
    if (name.contains('مدير النظام')) return PhosphorIconsBold.crown;
    if (name.contains('مالي')) return PhosphorIconsBold.chartLineUp;
    if (name.contains('فرع')) return PhosphorIconsBold.buildings;
    if (name.contains('كاشير')) return PhosphorIconsBold.cashRegister;
    if (name.contains('مخزن') || name.contains('مخزون') ||
        name.contains('مخزني')) {
      return PhosphorIconsBold.package;
    }
    if (name.contains('محاسب')) return PhosphorIconsBold.calculator;
    if (name.contains('مدير')) return PhosphorIconsBold.userGear;
    return PhosphorIconsBold.userCircle;
  }

  Color _roleTint(String name) {
    if (name.contains('مدير النظام')) return AppColors.primary;
    if (name.contains('مالي')) return const Color(0xFF0D9488);
    if (name.contains('فرع')) return const Color(0xFF6366F1);
    if (name.contains('كاشير')) return AppColors.success;
    if (name.contains('مخزن') || name.contains('مخزون') ||
        name.contains('مخزني')) {
      return AppColors.warning;
    }
    if (name.contains('محاسب')) return const Color(0xFF8B5CF6);
    if (name.contains('مدير')) return const Color(0xFF4A80E8);
    return AppColors.textMuted;
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'pos':
        return PhosphorIconsBold.storefront;
      case 'dashboard':
        return PhosphorIconsBold.chartPieSlice;
      case 'inventory':
        return PhosphorIconsBold.warehouse;
      case 'products':
        return PhosphorIconsBold.package;
      case 'categories':
        return PhosphorIconsBold.folders;
      case 'customers':
        return PhosphorIconsBold.users;
      case 'suppliers':
        return PhosphorIconsBold.truck;
      case 'purchases':
        return PhosphorIconsBold.shoppingCart;
      case 'sales':
        return PhosphorIconsBold.receipt;
      case 'offers':
        return PhosphorIconsBold.tag;
      case 'delivery':
        return PhosphorIconsBold.mapPin;
      case 'tables':
        return PhosphorIconsBold.table;
      case 'kitchen':
        return PhosphorIconsBold.cookingPot;
      case 'treasury':
        return PhosphorIconsBold.vault;
      case 'hr':
        return PhosphorIconsBold.identificationBadge;
      case 'reports':
        return PhosphorIconsBold.chartBar;
      case 'settings':
        return PhosphorIconsBold.gear;
      case 'users':
        return PhosphorIconsBold.userCircle;
      case 'system':
        return PhosphorIconsBold.desktop;
      case 'audit':
        return PhosphorIconsBold.clipboardText;
      case 'loyalty':
        return PhosphorIconsBold.medal;
      case 'distribution':
        return PhosphorIconsBold.truck;
      case 'einvoice':
        return PhosphorIconsBold.fileText;
      case 'accounting':
        return PhosphorIconsBold.bookOpen;
      case 'manufacturing':
        return PhosphorIconsBold.factory;
      case 'assets':
        return PhosphorIconsBold.buildings;
      case 'analytics':
        return PhosphorIconsBold.chartLineUp;
      case 'branches':
        return PhosphorIconsBold.buildingOffice;
      case 'critical_financial':
        return PhosphorIconsBold.shieldWarning;
      case 'bookings':
        return PhosphorIconsBold.calendarCheck;
      default:
        return PhosphorIconsBold.shieldCheck;
    }
  }

  Color _categoryTint(String category) {
    switch (category) {
      case 'pos':
        return AppColors.primary;
      case 'dashboard':
        return const Color(0xFF6366F1);
      case 'inventory':
        return const Color(0xFF8B5CF6);
      case 'products':
        return AppColors.info;
      case 'categories':
        return const Color(0xFF0891B2);
      case 'customers':
        return AppColors.success;
      case 'suppliers':
        return const Color(0xFFEA580C);
      case 'purchases':
        return const Color(0xFFD97706);
      case 'sales':
        return const Color(0xFF059669);
      case 'offers':
        return AppColors.warning;
      case 'delivery':
        return const Color(0xFFDB2777);
      case 'tables':
        return const Color(0xFF7C3AED);
      case 'kitchen':
        return const Color(0xFFDC2626);
      case 'treasury':
        return const Color(0xFF0D9488);
      case 'hr':
        return const Color(0xFF4F46E5);
      case 'reports':
        return const Color(0xFF2563EB);
      case 'settings':
        return const Color(0xFF64748B);
      case 'users':
        return const Color(0xFFE11D48);
      case 'system':
        return const Color(0xFF475569);
      case 'audit':
        return const Color(0xFF9333EA);
      case 'critical_financial':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }
}
