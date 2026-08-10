#!/usr/bin/env bash
# بوابة الجودة الواحدة — شغّلها بدل ما تفتكر السويّات.
#
# لماذا سكربت: في جلسة 2026-08-04 كانت السويّات الثلاث مكتوبة في الخطة
# ومع ذلك أُهملت `test/integration` عشر مهام كاملة، فكُسر اختبار واكتشفه
# وكيلٌ بالمصادفة. مستند لا يُنفَّذ ليس بوابة.
#
# ⚠️ ونفسُ العطل تكرّر في السكربت نفسه: كان يشغّل ستّ مجلداتٍ من اثني عشر،
#    فبقي **٩٨ ملفَ اختبار** (منها ٨١ للواجهات) خارجَ البوابة أشهراً بلا أن
#    يلاحظ أحد — والبوابةُ خضراء. ولذلك صار هنا حارسُ تغطيةٍ يفشل تلقائياً
#    لأيّ مجلدٍ يُضاف ولا يُشغَّل (مقيس 2026-08-09).
#
# الاستعمال:
#   scripts/gate.sh          # التغطية + analyze + كل السويّات المحلّية
#   scripts/gate.sh --pg     # ويضيف سويّة PostgreSQL الحيّة
#
# ويمكن تجاوز وصلة PostgreSQL بمتغيّر بيئة:
#   PG_TEST_DSN=postgres://… scripts/gate.sh --pg
set -uo pipefail

RC=0
step() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1"; RC=1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }

# ‏`--pg` يُقبَل في أيّ موضع. كان يُقرأ من `$1` وحده، فـ`gate.sh -x --pg`
# يتخطّى سويّة PostgreSQL **صامتاً** ويطبع «البوابة كلها خضراء».
WITH_PG=0
for a in "$@"; do [[ "$a" == "--pg" ]] && WITH_PG=1; done

# ─────────────────────────────────────────────────────────────────────────
# تنظيفٌ إلزاميّ قبل أيّ تشغيل
# ─────────────────────────────────────────────────────────────────────────
# ⚠️ `flutter test` ينهار بـ
#     PathExistsException: Cannot copy file to 'build\native_assets\windows\
#     sqlite3.dll' (errno = 183)
# لأن الملف **موجودٌ من تشغيلةٍ سابقة** فلا يقدر يستبدله. والعَرَضُ مضلّل: لو
# بقي الملفُّ مقفولاً انتظر المشغّل بلا استهلاكِ معالج، وفشل كلُّ ملفٍ تالٍ في
# طور **التحميل** بـTimeoutException بعد ١٢ دقيقة — ٣ ساعات و٢٤ دقيقة ضائعة
# في جلسة 2026-08-09.
#
# وكان مكتوباً هنا أن `--concurrency=1` إجباريٌّ لأن التوازي يُحدث الانهيار.
# **غلطٌ مقيس**: الانهيارُ وقع مع `--concurrency=1`. التوازي يزيد احتمالَ
# التصادم ولا يصنعه؛ العلّةُ بقايا الملف.
rm -rf build/native_assets

# ─────────────────────────────────────────────────────────────────────────
# التوازي — مقيسٌ لا مفترَض (2026-08-09، ١٦ نواة)
# ─────────────────────────────────────────────────────────────────────────
#   السويّة                         c=1            c=4          العدد
#   unit+data+structural+services   2861 / 1179s   2861 / 457s   مطابق
#   widget+core+domain+…             634 /  232s    634 / 107s   مطابق ×٢
#   integration                      641 /  604s    641 / 258s   مطابق
#
# تشغيلةُ 2026-08-10 بعد إغلاق بلوكرات PicPos (‏c=4، ١٦ نواة، ‏--pg):
#   analyze 6 info · unit 2970 · widget 651 · integration 676 · pg 45
#   (‏آخرُ تشغيلةٍ كاملةٍ على شجرةٍ ثابتة بعد إغلاق H8 · H11 · H13 · H14 · H15)
#
# والحكمُ **بتطابق عدد النجاحات** لا بالخضرة: لو كشف التوازي هشاشةً كامنة
# لظهر الفرقُ رقماً. وصفرُ `PathExistsException` في كلّ التشغيلات بعد تنظيف
# `build/native_assets` أعلاه.
LOCAL_CONCURRENCY="${GATE_CONCURRENCY:-4}"

# عملياتٌ يتيمة من تشغيلةٍ سابقة تحجز ذاكرةً وتقفل ملفات. تحذيرٌ لا فشل —
# قد تكون لخادم تحليلٍ في محرّر مفتوح.
if command -v powershell >/dev/null 2>&1; then
  ORPHANS="$(powershell -c "(Get-Process | Where-Object { \$_.ProcessName -match 'dart|flutter' } | Measure-Object).Count" 2>/dev/null | tr -d '\r[:space:]')"
  if [[ "${ORPHANS:-0}" =~ ^[0-9]+$ ]] && (( ORPHANS > 0 )); then
    warn "فيه $ORPHANS عملية dart/flutter شغّالة قبل البدء — لو مش محرّر مفتوح فهي يتيمة وبتحجز ذاكرة"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────
# ٠. حارسُ التغطية — قبل أيّ اختبار
# ─────────────────────────────────────────────────────────────────────────
# كلُّ مجلدٍ تحت `test/` فيه اختبارٌ لا بدّ أن تشغّله سويّةٌ أدناه. الحارسُ
# هنا لا في ملفٍ منفصل كي يُقرأ مع القائمة التي يحرسها.
COVERED_DIRS="unit data structural services core domain presentation security static widget integration integration_pg"
step "تغطيةُ المجلدات — كلُّ مجلدٍ فيه اختبارٌ لا بد أن يُشغَّل"
MISSING=""
for d in test/*/; do
  name="${d#test/}"; name="${name%/}"
  [[ -z "$(find "$d" -name '*_test.dart' -print -quit 2>/dev/null)" ]] && continue
  case " $COVERED_DIRS " in *" $name "*) ;; *) MISSING="$MISSING $name";; esac
done
if [[ -n "$MISSING" ]]; then
  fail "مجلداتُ اختبارٍ لا تشغّلها أيُّ سويّة:$MISSING — أضفها لسويّةٍ ولـCOVERED_DIRS"
else
  ok "تغطيةُ المجلدات — لا مجلدَ مهمَل"
fi

# ─────────────────────────────────────────────────────────────────────────
# سويّةٌ واحدة: تشغيل + كودُ خروج + **حدٌّ أدنى لعدد النجاحات**
# ─────────────────────────────────────────────────────────────────────────
# ⚠️ كودُ الخروج وحدَه لا يكفي: لو توقّف اكتشافُ مجلدٍ كامل (‏إعادةُ تسميةٍ،
#    أو نمطُ مسارٍ غلط) لخرج المشغّل بصفرٍ **وبقيت البوابة خضراء** — وهو
#    بالضبط ما أخفى ٩٨ ملفاً. فالحدُّ الأدنى يجعل الاختفاءَ مرئياً.
#
#    وهو **حدٌّ أدنى لا مساواة**: إضافةُ اختباراتٍ لا تكسر البوابة، ونقصانُها
#    يكسرها. من يحذف اختباراً عن قصدٍ يُنزل الرقم في نفس الكوميت.
run_suite() {
  local label="$1" min="$2"; shift 2
  step "$label   (حدٌّ أدنى: $min ناجح)"
  local log; log="$(mktemp)"
  "$@" 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  # عدّادُ النجاح تصاعديٌّ أثناء التشغيل، فأكبرُ `+N` هو النهائيّ. وغيابُه
  # كلياً (انهيارٌ قبل أوّل اختبار) يعطي صفراً فيسقط على الحدّ الأدنى.
  #
  # ⚠️ والالتقاطُ **مقيَّدٌ ببداية سطر التقدّم** `MM:SS +N`، لا أيّ `+رقم` في
  #    السجلّ: نصُّ اختبارٍ يطبع رقماً كهذا يرفع العدَّ المقيس فيمرُّ الحدُّ
  #    الأدنى زوراً. مقيس: التقاطُ `~N` غيرُ المقيَّد أعطى ٧٥٠ متخطّى بينما
  #    الحقيقة ٧ — الرقمُ جاء من مخرجات اختبار.
  local passed
  passed="$(grep -oE '^[0-9]{2,}:[0-9]{2} \+[0-9]+' "$log" \
            | grep -oE '[0-9]+$' | sort -n | tail -1)"
  passed="${passed:-0}"
  rm -f "$log"
  if [[ $rc -ne 0 ]]; then
    fail "$label — فيه اختباراتٌ فاشلة ($passed ناجح)"
  elif (( passed < min )); then
    fail "$label — $passed ناجح فقط والحدُّ الأدنى $min ⇒ اختباراتٌ اختفت"
  else
    ok "$label — $passed ناجح"
  fi
}

step "flutter analyze lib test   (خط الأساس: 6 info)"
# ⚠️ `flutter analyze` بيخرج بكود ≠ 0 لو فيه **أي** ملاحظة، حتى `info`. وخط
#    الأساس هنا ٦ info، فربط البوابة بكود الخروج كان بيخلّيها حمرا دايماً
#    ويخبّي الفشل الحقيقي. البوابة بتفشل على `error`/`warning` بس، وبتطبع
#    عدد الـinfo عشان أي انحراف عن الـ٦ يبان.
ANALYZE_OUT="$(flutter analyze lib test 2>&1)"
printf '%s\n' "$ANALYZE_OUT" | grep -E ' (error|warning|info) - ' || true
INFO_COUNT="$(printf '%s\n' "$ANALYZE_OUT" | grep -cE ' info - ' || true)"
if printf '%s\n' "$ANALYZE_OUT" | grep -qE ' (error|warning) - '; then
  fail "analyze — فيه error/warning"
elif [[ "$INFO_COUNT" -ne 6 ]]; then
  fail "analyze — عدد الـinfo $INFO_COUNT مش ٦ (انحراف عن خط الأساس)"
else
  ok "analyze — ٦ info بالظبط"
fi

# الحدود مقيسةٌ 2026-08-10 بعد جلسة إغلاق بلوكرات PicPos.
run_suite "unit + data + structural + services" 2970 \
  flutter test test/unit test/data test/structural test/services --concurrency="$LOCAL_CONCURRENCY"

# الواجهات والنطاقُ والنواة — كانت **كلُّها** خارج البوابة حتى 2026-08-09.
run_suite "widget + core + domain + presentation + security + static" 651 \
  flutter test test/core test/domain test/presentation test/security \
              test/static test/widget test/widget_test.dart --concurrency="$LOCAL_CONCURRENCY"

run_suite "integration" 676 \
  flutter test test/integration --concurrency="$LOCAL_CONCURRENCY"

if (( WITH_PG )); then
  # ⚠️ bootPgTestSchema() ينفّذ DROP SCHEMA public CASCADE — قاعدة picpos فقط.
  #    uralcash و Avalon على نفس الخادم وفيهما بيانات.
  #
  # 🔴 و`--concurrency=1` هنا **قيدٌ معماريّ لا يُقاس بتجربة**: عشرةُ ملفاتٍ
  #    تنادي `bootPgTestSchema()` وكلٌّ منها يُسقط سكيما `public` على **نفس
  #    القاعدة** (‏DSN واحد). فعند التوازي يمسح ملفٌّ سكيما ملفٍّ آخر أثناء
  #    عمله — ويفشل **أحياناً**، وهو أسوأ من الفشل الدائم لأنه يُقرأ تذبذباً.
  #    عزلُها يحتاج قاعدةً لكل عامل، لا رفعَ الرقم.
  export PG_TEST_DSN="${PG_TEST_DSN:-postgres://postgres:14590@127.0.0.1:5432/picpos}"
  run_suite "integration_pg — PostgreSQL حيّة" 45 \
    flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1
fi

printf '\n'
if [[ $RC -eq 0 ]]; then ok "البوابة كلها خضراء"; else fail "البوابة حمراء — لا تشحن"; fi
exit $RC
