# patch: إغلاق إجباري للوردية قبل تسجيل الخروج

**الملف:** `logout-shift-enforcement.diff` — يمسّ `lib/presentation/shell/app_shell.dart` فقط (ملف مشترك أصله UralCash).

## الغرض
كان المستخدم يقدر يسجّل خروج وعنده وردية مفتوحة، فتتعلّق دون ترصيد معاملاتها
(سيناريو: أدمن بدأ وردية، اشتغل، نسي يقفلها، سجّل خروج، ودخل بعده كاشير — فتبقى
وردية الأدمن مفتوحة بلا ترصيد). الآن عند تسجيل الخروج، لو المستخدم عنده وردية
مفتوحة (`getCurrentOpenShift`) يظهر تنبيه إلزامي: **يجب إغلاق الوردية أولاً**
(ديالوج الإغلاق `PosCashierClosingDialog` يسجّل الخروج تلقائياً بعد الإغلاق الناجح).
**لا تجاوز — حتى للأدمن** (قرار صاحب المشروع).

## التطبيق (يعمله صاحب المشروع على UralCash)
```bash
git -C D:/URAL-ERP apply --3way patches-for-uralcash/logout-shift-enforcement.diff
```
تغيير محايد للعلامة، صفر إشارات `Brand.`، صفر ملفات PicPos — يستخدم
`PosCashierClosingDialog` و`treasuryRepositoryProvider` الموجودين عند الطرفين.
