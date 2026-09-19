// حقائقُ الحساب المشتقّة — **قاعدةٌ واحدةٌ يقرؤها الكاتبُ والعرض**.
//
// ═══ 🔴 فئةُ العطب ═══
//
// هجرةُ v110 أضافت `normal_balance` و`level` **وملأتهما بقاعدةٍ صريحة**:
//
//   UPDATE accounts SET normal_balance = 'credit'
//     WHERE account_type IN ('liability','equity','revenue');
//   UPDATE accounts SET level = 2 WHERE parent_id IN (… جذور …);
//
// فالنظامُ يعرف القاعدة — **و`createAccount` لا يقرؤها**. فكلُّ حسابٍ أُنشئ
// من الشاشة منذ v110 وقع على افتراضات العمود (`'debit'` و`1`)، أي أنّ حسابَ
// إيراداتٍ جديداً **يناقض قاعدةَ الهجرة نفسِها**.
//
// ⚠️ **ولذلك تعيش القاعدةُ هنا لا في SQL الهجرة وحدَها**: نسختان تفترقان
// بأوّل نوعِ حسابٍ يُضاف، والهجرةُ تعمل مرّةً والكاتبُ كلَّ يوم.

/// طبيعةُ الرصيد من نوع الحساب — `debit` أو `credit`.
///
/// ⚠️ **ونوعٌ غيرُ معروفٍ يقع على `debit` ولا يرمي**: هذا حقلٌ **مشتقٌّ**،
/// وإفشالُ إنشاءِ حسابٍ لأجله يمنع عملاً صحيحاً بسبب وصفٍ تابع. والأنواعُ
/// الخمسةُ مغلقةٌ في `account_type` على أيّ حال.
String normalBalanceFor(String accountType) =>
    const {'liability', 'equity', 'revenue'}.contains(accountType)
        ? 'credit'
        : 'debit';

/// مستوى الحساب من مستوى أبيه.
///
/// ⚠️ **و`null` يعني جذراً** لا «غيرَ معروف»: الجذرُ مستواه ١، وهو ما تكتبه
/// الهجرةُ حرفاً (`SET level = 1 WHERE parent_id IS NULL`).
int accountLevelUnder(int? parentLevel) =>
    parentLevel == null ? 1 : parentLevel + 1;

/// طبيعةُ الحساب: أبٌ لا يُرحَّل عليه، أم تفصيليٌّ يُرحَّل.
///
/// ⚠️ **وهذه اختيارُ مستخدمٍ لا اشتقاق**: حسابٌ بلا أبناءَ اليومَ قد يصير
/// أباً غداً، وحسابٌ له أبناءٌ قد يُرحَّل عليه في دليلٍ قديم. فالاشتقاقُ من
/// وجود الأبناء كان سيُبدّل طبيعةَ حسابٍ تحت المستخدم بلا أن يطلب.
const String kAccountNatureView = 'view';
const String kAccountNatureDetail = 'detail';
