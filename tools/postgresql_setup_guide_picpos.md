# دليل إعداد PostgreSQL لنظام PicPos
## ربط السيرفر والفروع

---

## المتطلبات

| العنصر | التفاصيل |
|--------|----------|
| **نظام التشغيل** | Windows 10/11 أو Windows Server 2016+ |
| **جهاز السيرفر** | RAM: 4GB+ / مساحة: 20GB+ |
| **الشبكة** | IP ثابت داخلي للسيرفر (مثلاً `192.168.1.100`) |
| **للفروع الخارجية** | IP ثابت من مزود الإنترنت أو خدمة DDNS |

---

## الخطوة 1: تثبيت PostgreSQL على السيرفر

### 1.1 تحميل PostgreSQL
1. اذهب إلى: **https://www.postgresql.org/download/windows/**
2. اختر **Download the installer** → حمّل آخر إصدار (16+)
3. شغّل الملف المحمّل كـ **Administrator**

### 1.2 خطوات التثبيت
1. **اختر مكان التثبيت** → الافتراضي مقبول
2. **اختر المكونات** → تأكد من تحديد:
   - ✅ PostgreSQL Server
   - ✅ pgAdmin 4 (واجهة إدارة)
   - ✅ Command Line Tools
3. **مجلد البيانات** → الافتراضي مقبول
4. **كلمة مرور المسؤول (postgres)** → **اختر كلمة مرور قوية واحفظها!**
5. **البورت** → اتركه `5432` (الافتراضي)
6. **اللغة** → `Arabic, Egypt` أو `Default Locale`
7. أكمل التثبيت

---

## الخطوة 2: إنشاء قاعدة البيانات والمستخدم

### 2.1 افتح pgAdmin 4
1. من قائمة Start → ابحث عن **pgAdmin 4** وافتحه
2. اتصل بالسيرفر المحلي (localhost) بكلمة مرور `postgres`

### 2.2 إنشاء مستخدم خاص
1. وسّع **Servers** → **PostgreSQL** → **Login/Group Roles**
2. **كليك يمين** → **Create** → **Login/Group Role**
3. أدخل:
   - **General** → Name: `picpos`
   - **Definition** → Password: `[اختر كلمة مرور قوية]`
   - **Privileges** → ✅ Can login? = Yes
4. اضغط **Save**

### 2.3 إنشاء قاعدة البيانات
1. اضغط **كليك يمين** على **Databases** → **Create** → **Database**
2. أدخل:
   - **Database**: `picpos`
   - **Owner**: `picpos`
3. اضغط **Save**

### بديل: استخدام سطر الأوامر (psql)
```sql
-- افتح PowerShell كـ Admin وشغّل:
-- "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres

CREATE USER picpos WITH PASSWORD 'كلمة_المرور_هنا';
CREATE DATABASE picpos OWNER picpos;
GRANT ALL PRIVILEGES ON DATABASE picpos TO picpos;
```

---

## الخطوة 3: السماح بالاتصال من الشبكة

### 3.1 تعديل postgresql.conf
1. اذهب إلى مجلد بيانات PostgreSQL:
   ```
   C:\Program Files\PostgreSQL\16\data\
   ```
2. افتح ملف **`postgresql.conf`** بالمحرر (كـ Admin)
3. ابحث عن `listen_addresses` وعدّله إلى:
   ```
   listen_addresses = '*'
   ```
4. احفظ الملف

### 3.2 تعديل pg_hba.conf
1. في نفس المجلد، افتح **`pg_hba.conf`**
2. أضف السطر التالي في نهاية الملف:

**للشبكة المحلية (LAN):**
```
host    picpos    picpos    192.168.1.0/24    md5
```

**لأي IP (الفروع الخارجية عبر الإنترنت):**
```
host    picpos    picpos    0.0.0.0/0    md5
```

3. احفظ الملف

### 3.3 إعادة تشغيل خدمة PostgreSQL
1. افتح **Services** (من قائمة Start ابحث عن services.msc)
2. ابحث عن **postgresql-x64-16** (أو الإصدار الخاص بك)
3. اضغط **Restart**

---

## الخطوة 4: إعداد الشبكة

### 4.1 الشبكة المحلية (LAN — نفس المكان)
**لا يحتاج إعداد إضافي** — فقط تأكد:
1. السيرفر والأجهزة على **نفس الشبكة** (مثلاً `192.168.1.x`)
2. اعرف **IP السيرفر**: افتح CMD على السيرفر وشغّل `ipconfig`
3. استخدم الـ IP في إعدادات البرنامج (مثلاً `192.168.1.100`)

### 4.2 الفروع الخارجية (WAN — عبر الإنترنت)

#### خيار أ: IP ثابت من شركة الإنترنت (الأفضل)
1. اتصل بمزود الإنترنت واطلب **IP ثابت** (Static Public IP)
2. ادخل إعدادات الراوتر → **Port Forwarding**:
   - **External Port**: `5432`
   - **Internal IP**: عنوان السيرفر المحلي (مثلاً `192.168.1.100`)
   - **Internal Port**: `5432`
   - **Protocol**: TCP
3. استخدم الـ IP الثابت في إعدادات البرنامج بالفروع

#### خيار ب: DDNS (بديل مجاني بدون IP ثابت)
1. سجّل حساب مجاني في **https://www.noip.com** أو **https://www.duckdns.org**
2. اختر اسم نطاق مثل: `picpos-server.ddns.net`
3. حمّل **DUC (Dynamic Update Client)** على السيرفر — يحدّث الـ IP تلقائياً
4. أعد **Port Forwarding** كما في خيار أ
5. استخدم `picpos-server.ddns.net` كعنوان السيرفر في البرنامج

### 4.3 فتح جدار الحماية (Firewall)
على جهاز السيرفر:
```powershell
# افتح PowerShell كـ Admin وشغّل:
New-NetFirewallRule -DisplayName "PostgreSQL" -Direction Inbound -Protocol TCP -LocalPort 5432 -Action Allow
```

---

## الخطوة 5: إعداد التطبيق

### 5.1 على كل جهاز (فرع أو رئيسي):
1. افتح **PicPos**
2. اذهب إلى **الإعدادات** → **قاعدة البيانات والسيرفر**
3. اختر وضع **سيرفر (PostgreSQL)**
4. أدخل البيانات:

| الحقل | القيمة |
|-------|--------|
| **عنوان السيرفر** | `192.168.1.100` (LAN) أو `picpos-server.ddns.net` (WAN) |
| **البورت** | `5432` |
| **اسم قاعدة البيانات** | `picpos` |
| **اسم المستخدم** | `picpos` |
| **كلمة المرور** | كلمة المرور اللي عملتها |
| **SSL** | ❌ (للشبكة المحلية) / ✅ (للإنترنت) |

5. اضغط **اختبار الاتصال** ← تأكد من ظهور ✓
6. اضغط **حفظ وتطبيق**
7. أعد تشغيل التطبيق

---

## الخطوة 6: التحقق من العمل

1. **على الجهاز 1:** سجّل دخول → أضف صنف تجريبي
2. **على الجهاز 2:** سجّل دخول → تأكد من ظهور الصنف فوراً
3. **على الجهازين:** أجرِ عملية بيع واحدة من كل جهاز → تحقق من التقارير

---

## استكشاف الأخطاء

| المشكلة | الحل |
|---------|------|
| **فشل الاتصال** | تأكد أن خدمة PostgreSQL تعمل على السيرفر |
| **Connection refused** | تحقق من `listen_addresses = '*'` في postgresql.conf |
| **Authentication failed** | تأكد من اسم المستخدم وكلمة المرور وإعدادات pg_hba.conf |
| **لا يمكن الوصول من فرع خارجي** | تحقق من Port Forwarding وجدار الحماية |
| **بطء الاتصال** | تحقق من سرعة الإنترنت — PostgreSQL يحتاج اتصال مستقر |

---

## النسخ الاحتياطي لـ PostgreSQL

### نسخ احتياطي يدوي:
```powershell
"C:\Program Files\PostgreSQL\16\bin\pg_dump.exe" -U picpos -h localhost picpos > backup_2024.sql
```

### استعادة:
```powershell
"C:\Program Files\PostgreSQL\16\bin\psql.exe" -U picpos -h localhost picpos < backup_2024.sql
```

### نسخ احتياطي تلقائي (مهمة مجدولة):
1. أنشئ ملف `backup.bat` يحتوي على أمر pg_dump أعلاه
2. افتح **Task Scheduler** → أنشئ مهمة جديدة → شغّل الملف يومياً

---

> **ملاحظة:** عند العودة للوضع المحلي (SQLite)، اذهب لنفس الإعدادات واختر "محلي (SQLite)" ثم أعد تشغيل التطبيق.
