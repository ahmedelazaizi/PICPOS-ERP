# سلامة الإصدار: التوقيع، البصمات، والمتطلبات المنزَّلة

يغطي نتائج التدقيق B-01 وB-02 وB-03 في [part3-secrets-supplychain.md](<part3-secrets-supplychain.md>).

## ١ · الوضع الحالي

- **لا يوجد توقيع Authenticode حاليًا** لـ`PicPos.exe` ولا للمثبّت (المالك لا يملك شهادة توقيع كود). لذلك قد يعرض ويندوز تحذير SmartScreen «ناشر غير معروف». هذا متوقع ولا يعني بالضرورة أن الملف معطوب.
- **المثبّت لا يضيف أي شهادة** إلى مخازن الثقة (لا `Root` ولا `TrustedPublisher`) — أُزيلت خطوة `certutil -addstore` نهائيًا (B-01). القرار: إضافة جذر موثوق على أجهزة العملاء خطر أكبر من فائدتها؛ الحل الصحيح شهادة توقيع معتمدة (القسم ٤).
- بدلًا من التوقيع نعتمد **بصمة SHA-256** تُنشر مع كل إصدار في `SHA256SUMS.txt`.
- ما يُنزَّل أثناء التثبيت (VC++ وPostgreSQL) لا يُنفَّذ إلا بعد مطابقة SHA-256 مثبَّتة داخل `installer/setup.iss`؛ عند عدم التطابق يُحذف الملف ويتوقف التثبيت برسالة واضحة (B-03).

## ٢ · للناشر: توليد `SHA256SUMS.txt`

بعد بناء المثبّت (`build_picpos.bat` ثم `build_installer_picpos.bat`) وتجهيز ملف zip إن وُجد:

```powershell
powershell -ExecutionPolicy Bypass -File tool\make_release_checksums.ps1
# أو لإصدار محدد:
powershell -ExecutionPolicy Bypass -File tool\make_release_checksums.ps1 -Version 3.9.1.275
```

يقرأ الإصدار من `#define AppVersion` في `setup.iss`، ويجمع `installer\output\PicPos-Setup-<الإصدار>.exe` (إلزامي) و`.zip` (إن وُجد)، ويكتب `installer\output\SHA256SUMS.txt` بصيغة `sha256sum`. **انشر الملف مع أصول الإصدار** (GitHub Release) وانسخ البصمة أيضًا في نص الإصدار.

> الملف `tool/make_release_checksums.ps1` مُتجاهَل بسبب `*.ps1` في `.gitignore`، فيُضاف مرة واحدة بـ`git add -f tool/make_release_checksums.ps1`. وكذلك `.gitignore` يتجاهل `*.bat`؛ أما `tool/sign_file.cmd` فغير مُتجاهَل.

## ٣ · للعميل: التحقق من البصمة قبل التشغيل

1. نزّل المثبّت و`SHA256SUMS.txt` من صفحة الإصدار الرسمية نفسها.
2. في PowerShell احسب بصمة الملف المنزَّل:

   ```powershell
   Get-FileHash .\PicPos-Setup-<الإصدار>.exe -Algorithm SHA256
   ```

   أو في موجّه الأوامر: `certutil -hashfile PicPos-Setup-<الإصدار>.exe SHA256`
3. قارن القيمة بالسطر المقابل في `SHA256SUMS.txt` (حروف كبيرة/صغيرة لا تهم). **إن اختلفت ولو بحرف واحد فلا تشغّل الملف** وأبلغ الدعم.
4. لا فائدة من البصمة إذا نُزّل `SHA256SUMS.txt` من مصدر غير موثوق؛ خذه من القناة الرسمية (أو من الدعم مباشرةً).

## ٤ · تفعيل التوقيع لاحقًا (عند الحصول على شهادة)

البنية جاهزة وتعمل **فقط** عند ضبط متغيرات بيئة؛ بدونها يطبع البناء `unsigned build` ويكمل بلا توقيع. لا أسرار في الريبو.

1. احصل على شهادة توقيع كود معتمدة (OV أو EV، أو Azure Trusted Signing) — لا شهادة ذاتية التوقيع.
2. ثبّت Windows SDK (يوفّر `signtool.exe`) أو اضبط `PICPOS_SIGNTOOL` على مساره الكامل.
3. اضبط **أحد** الخيارين في بيئة جهاز البناء فقط (لا في ملف داخل الريبو):
   - ملف PFX: `PICPOS_SIGN_PFX` (المسار) و`PICPOS_SIGN_PFX_PASSWORD` (كلمة المرور إن وُجدت).
   - شهادة في مخزن ويندوز أو توكن عتاد: `PICPOS_SIGN_THUMBPRINT` (بصمة SHA-1 للشهادة).
   - اختياري: `PICPOS_SIGN_TIMESTAMP_URL` (الافتراضي `http://timestamp.digicert.com`).
4. شغّل `build_picpos.bat`: يوقّع `PicPos.exe` و`sqlite3.dll` (بعد استبدال نسخة SQLCipher) عبر `tool\sign_file.cmd` بـ`/fd sha256 /tr … /td sha256`. وكذلك `build_release.bat` (UralCash).
5. شغّل `build_installer_picpos.bat`: يمرّر `/DSignInstaller=1` فيفعّل `SignTool=` و`SignedUninstaller=yes` في `setup.iss` فيوقَّع المثبّت وبرنامج إزالة التثبيت.
6. تحقّق: `signtool verify /pa /v PicPos-Setup-<الإصدار>.exe` ثم ولّد `SHA256SUMS.txt` **بعد** التوقيع (التوقيع يغيّر البصمة).
7. إن طُلب توقيع ولم يُعثر على `signtool` أو فشل، **يفشل البناء** (لا يُنتج إصدارًا موقّعًا جزئيًا).
8. للتوقيع في CI (`.github/workflows`): مرّر الشهادة كسرّ GitHub مشفّر وفكّها إلى ملف مؤقت يُحذف بعد الخطوة (خارج نطاق هذا التغيير).

## ٥ · تحديث بصمات المتطلبات المثبَّتة في `setup.iss`

| المكوّن | المصدر | الحالة المثبَّتة |
|---|---|---|
| VC++ x64 | `https://aka.ms/vs/17/release/vc_redist.x64.exe` (رابط «الأحدث» لمايكروسوفت) | 14.44.35211.0، التوقيع Valid من Microsoft Corporation |
| PostgreSQL | `https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64.exe` | 16.4-1، التوقيع Valid من EnterpriseDB Corporation |

- رابط VC++ متحرّك: عندما تُصدر مايكروسوفت نسخة أحدث سيرفض المثبّت الملف برسالة عدم تطابق. الإجراء: نزّل الملف من الرابط، تأكد من `Get-AuthenticodeSignature` (Valid وناشره Microsoft Corporation)، احسب `Get-FileHash -Algorithm SHA256`، حدّث `VCRedistSha256` في `setup.iss` وأعد البناء.
- بصمة PostgreSQL محسوبة من التنزيل الرسمي مباشرةً ولم تُقارَن بقيمة منشورة من EDB؛ راجعها عند أي ترقية للإصدار (والإصدار 16.4 قديم ويستحق الترقية لاحقًا).
