const fs = require('fs');
const r = process.argv[2];
function between(file, startRe, endRe) {
  const s = fs.readFileSync(r + '/' + file, 'utf8');
  const a = s.search(startRe);
  if (a < 0) return null;
  const rest = s.slice(a);
  const b = rest.search(endRe);
  return b < 0 ? null : rest.slice(0, b);
}
function names(block, re) {
  if (block === null) return 'PATTERN-FAIL';
  const m = block.match(re) || [];
  return new Set(m).size;
}
console.log('خط الأساس        = ' + names(
  between('test/structural/sync_coverage_guard_test.dart', /const _unsyncedBaseline/, /\r?\n};/),
  /'[A-Za-z][A-Za-z0-9]*'/g));
console.log('pullTables       = ' + names(
  between('lib/services/delta_pull_service.dart', /static const List<String> pullTables/, /\r?\n  \];/),
  /'[a-z_]+'/g));
console.log('deltaOnlyTables  = ' + names(
  between('lib/services/delta_pull_service.dart', /static const Set<String> deltaOnlyTables/, /\r?\n  };/),
  /'[a-z_]+'/g));
console.log('branchScoped     = ' + names(
  between('lib/services/delta_pull_service.dart', /static const Set<String> branchScopedPullTables/, /\r?\n  };/),
  /'[a-z_]+'/g));
