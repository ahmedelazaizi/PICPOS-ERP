#!/usr/bin/env bash
# بوابة الجودة الواحدة — شغّلها بدل ما تفتكر السويّات.
#
# لماذا سكربت: في جلسة 2026-08-04 كانت السويّات الثلاث مكتوبة في الخطة
# ومع ذلك أُهملت `test/integration` عشر مهام كاملة، فكُسر اختبار واكتشفه
# وكيلٌ بالمصادفة. مستند لا يُنفَّذ ليس بوابة.
#
# ملاحظة: --concurrency=1 إجباري — flutter test ينهار عند التوازي
# بـPathExistsException على sqlite3.dll. ولا تشغّل نسختين معاً.
#
# الاستعمال:
#   scripts/gate.sh          # analyze + unit + integration  (البوابة الإلزامية)
#   scripts/gate.sh --pg     # ويضيف سويّة PostgreSQL الحيّة
set -uo pipefail

RC=0
step() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1"; RC=1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

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

step "unit + data + structural + services   (خط الأساس: 2861 ناجح · 7 متخطّى)"
if flutter test test/unit test/data test/structural test/services --concurrency=1; then
  ok "unit"
else
  fail "unit"
fi

step "integration   (خط الأساس: 641 ناجح · 1 متخطّى)"
if flutter test test/integration --concurrency=1; then ok "integration"; else fail "integration"; fi

if [[ "${1:-}" == "--pg" ]]; then
  step "integration_pg — PostgreSQL حيّة   (خط الأساس: 45 ناجح)"
  # ⚠️ bootPgTestSchema() ينفّذ DROP SCHEMA public CASCADE — قاعدة picpos فقط.
  #    uralcash و Avalon على نفس الخادم وفيهما بيانات.
  if PG_TEST_DSN="postgres://postgres:14590@127.0.0.1:5432/picpos" \
     flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1; then
    ok "integration_pg"
  else
    fail "integration_pg"
  fi
fi

printf '\n'
if [[ $RC -eq 0 ]]; then ok "البوابة كلها خضراء"; else fail "البوابة حمراء — لا تشحن"; fi
exit $RC
