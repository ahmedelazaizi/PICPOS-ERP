// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class SettingSyncStrategy extends SyncStrategy {
  SettingSyncStrategy(super.db);

  @override
  String get tableName => 'settings';

  @override
  String get apiEndpoint => '/api/settings';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final settingsMap = json['settings'] as Map<String, dynamic>;

    // إعدادات خاصة بالجهاز أو الفرع لا يجب طمسها من السيرفر الرئيسي
    // القائمةُ ثابتٌ مُصدَّرٌ في ذيل الملفّ — يقرؤها الكاتبُ أيضاً.
    for (final entry in settingsMap.entries) {
      if (!isDeviceLocalSettingKey(entry.key)) {
        await db.setSetting(entry.key, entry.value?.toString() ?? '');
      }
    }
    // Force UI refresh after sync
    if (settingsMap.isNotEmpty) {
      db.markTablesUpdated({db.settings});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    // Settings are handled differently in the DB (key-value pair)
    // For now, this is not used via generic upsert in the same way
    throw UnimplementedError('SettingSyncStrategy uses setSetting instead of upsert');
  }
}

/// مفاتيحُ الإعدادات التي تحمل **سرّاً** فلا تخرج من الخادم عبر الـAPI ولا
/// تُكتَب إليه من عميل.
///
/// ⚠️ **محورٌ مختلفٌ عن [kDeviceLocalSettingKeys] — لا تخلط بينهما.** تلك
/// «يخصُّ هذا الجهاز»، وهذه «سرٌّ لا يُذاع». مفتاحٌ قد يكون في الاثنتين أو
/// في واحدة. وحشرُ الأسرار في قائمة الجهاز كان سيمنع مزامنتَها أيضاً —
/// وذلك قرارٌ آخر له أثرٌ تشغيليّ (‏الأجهزةُ تتحقّق من كلمة المدير محلّيّاً).
///
/// ── ما تغلقه هذه القائمة، مقيساً ────────────────────────────────────────
/// • `GET /api/settings` كان **يُفرغ جدولَ الإعدادات كاملاً** بلا بوّابةِ
///   صلاحيّةٍ إطلاقاً — فيسلّم `admin_password_hash` و`admin_password_salt`
///   لأيِّ حاملِ توكن LAN. والهاشُ سلسلةُ SHA‑256 مكرَّرةٌ (‏ملحُها يدخل في
///   الدورة الأولى وحدَها) فكسرُه دون اتّصالٍ رخيصٌ جدّاً.
/// • `POST /api/settings` كان يكتب أيَّ مفتاح. فمن يملك `settings_edit` —
///   أو المستخدمُ رقم ١ — كان **يستبدل كلمةَ مرور المدير عن بُعد**، وهي
///   البوّابةُ التي تحرس تجاوزَ الصلاحيّات كلَّه. تصعيدُ امتيازٍ كامل.
///
/// وتشمل حسابَ المطوِّر كذلك: نفسُ العطب حرفيّاً في `developer_auth_service`.
const List<String> kServerSecretSettingKeys = <String>[
  'admin_password',       // النصُّ الصريحُ القديم — يبقى صفّاً فارغاً بعد الهجرة
  'admin_password_hash',
  'admin_password_salt',
  'developer_password_hash',
  'developer_password_salt',
];

/// هل [key] سرٌّ لا يُقرأ عبر الـAPI ولا يُكتَب منه؟
bool isServerSecretSettingKey(String key) =>
    kServerSecretSettingKeys.contains(key);

/// بادئةُ العلامات المائيّة: `_watermark__<tableName>`.
///
/// 🔴 **هذه أخطرُ مفاتيح الجهاز على الإطلاق، وكانت خارجَ الحماية.**
/// [kDeviceLocalSettingKeys] مطابقةٌ تامّةٌ فقط، والعلاماتُ المائيّةُ مفاتيحُ
/// **مشتقّةٌ باسم الجدول** فلا يمكن سردُها. وهي تعيش في نفس جدول `settings`،
/// فكانت تُدفَع صاعدةً وتُكتَب هابطةً كأيِّ إعدادٍ عادّيّ.
///
/// والأثرُ صامتٌ ودائم: العلامةُ تقول «سحبتُ كلَّ شيءٍ حتّى اللحظة س».
/// فجهازٌ يدفع علامتَه إلى الخادم، أو خادمٌ يكتب علامتَه فوق علامة جهازٍ
/// متأخّر، يُقدِّم المؤشِّرَ إلى الأمام فوق صفوفٍ **لم تُسحَب قطّ** — ولا
/// تُسحَب بعدها أبداً، لأنّ السحبَ التاليَ يبدأ من المؤشِّر المزيَّف. لا خطأ،
/// ولا سجلّ، ولا فرقٌ ظاهرٌ إلّا صفوفٌ ناقصةٌ إلى الأبد.
const String kWatermarkSettingPrefix = '_watermark__';

/// هل يخصُّ [key] هذا الجهازَ وحدَه فلا يُشارَك في أيِّ اتّجاه؟
///
/// المرجعُ الوحيدُ للطرفَين: الكتابةُ الهابطةُ من الخادم
/// ([SettingSyncStrategy.syncFromJson]) والدفعُ الصاعدُ
/// (`OfflineFallbackSyncService` وشاشاتُ الإعدادات و`postSettings`).
bool isDeviceLocalSettingKey(String key) =>
    kDeviceLocalSettingKeys.contains(key) ||
    key.startsWith(kWatermarkSettingPrefix);

/// مفاتيحُ الإعدادات التي تخصُّ **هذا الجهاز** ولا تُشارَك.
///
/// ⚠️ **تُقرأ من طرفَين، وإغفالُ أحدهما يُبطل الآخر.**
/// `SettingSyncStrategy` تمنع بها الكتابةَ الهابطةَ من الخادم فوق المفتاح،
/// وشاشاتُ الإعدادات تمنع بها دفعَه **صاعداً**. ومفتاحٌ محميٌّ من الهبوط
/// لكنّه يُدفَع صاعداً يصير قيمةَ الخادم ثمّ يُبَثّ إلى كلِّ الأجهزة — أي
/// أنّ خيارَ طرفيّةٍ واحدةٍ يدهس الجميعَ من بابٍ خلفيّ.
const kDeviceLocalSettingKeys = <String>[
      // ── Device identity / mode ──────────────────────────────────────
      // Spec 089: network_mode and deployment_mode are per-device. The
      // server stores 'server'; the client stores 'client'. Writing the
      // server's value into the client's DB causes the client to restart
      // as a server on the next boot (reconcileWithDb sees DB='server'
      // and promotes it). These keys MUST never be overwritten by sync.
      'network_mode',
      'deployment_mode',
      // Wizard completion flags are also per-device — overwriting them
      // with the server's value skips the wizard on a fresh client
      // install or incorrectly marks first-sync as done.
      'setup_completed',
      // First-run wizard v2 draft/progress: per-device, never synced.
      'setup_draft_v2',
      'setup_progress_v2',
      'client_first_sync_completed',
      // Mirror (Spec 131) uses the same first-sync contract. These flags are
      // per-device too — if the server payload ever carries them they must NOT
      // be written mid-performFirstSync (would flip isFirstSyncPending false
      // before the seeded-data wipe, leaving partial seeded master data — R8).
      'mirror_first_sync_completed',
      'mirror_cache_integrity_v1_applied',
      // client_branch_id records which branch THIS device belongs to.
      // The server has no client_branch_id of its own, but guard it
      // defensively so a misconfigured server row never clobbers the
      // client's branch assignment.
      'client_branch_id',
      // ── POS hardware mappings (per-terminal) ────────────────────────
      'pos_cash_safe_id',
      'pos_bank_safe_id',
      'pos_click_safe_id',
      'pos_default_warehouse_id',
      'device_id',
      'machine_id',
      'pos_receipt_printer',
      'pos_kitchen_printer',
      // سياسةُ البيع السريع §٤ — قرارُ المالك 2026-08-29: هذان لكلِّ جهازٍ لا
      // عامّان. `pos_open_drawer_on_print` خاصّيّةُ عتادٍ: نقطةُ بيعٍ بلا درجٍ
      // كانت سترث إعدادَ من عنده درج. و`pos_receipt_template` يُحسَم أصلاً
      // بالفرع والطابعة واللغة، فتثبيتُه مركزيّاً يتجاوز تلك السلسلة.
      // أُضيفا **قبل** التوصيل عمداً — تغييرُ النطاق بعد انتشار المفتاح على
      // أجهزةٍ حقيقيّةٍ أصعبُ بكثير.
      'pos_open_drawer_on_print',
      'pos_receipt_template',
      // Feature 031 — touch keyboard is per-device hardware preference
      // (FR-019). Server never overrides what the operator picked at
      // each terminal.
      'touchMode',
];
