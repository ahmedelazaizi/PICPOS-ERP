[CmdletBinding()]
param(
  [switch]$WhatIf = $true,
  [switch]$Apply,
  [ValidateRange(1, 65535)][int]$Port = 5432,
  [string]$DbHost = '127.0.0.1',
  [string]$Database = 'picpos',
  [string]$User = 'picpos',
  [string]$ConfirmOwnerDb
)
$ErrorActionPreference = 'Stop'
$TargetId = 2

if ($DbHost -notin @('127.0.0.1', 'localhost')) {
  throw 'لأسباب السلامة، يقبل هذا السكربت اتصالاً محلياً فقط.'
}
if (-not $Apply) {
  Write-Host ('WhatIf: سوف يفحص FK للسنة {0} على {1}:{2}/{3}، ثم يعطّل deleted_at فقط إذا لم توجد مراجع؛ لن تتغير القيود أو الأرصدة.' -f $TargetId, $DbHost, $Port, $Database)
  Write-Host 'للتنفيذ الصريح أعد التشغيل مع -Apply. لم يُجر أي اتصال أو تعديل.'
  exit 0
}
if ($Port -eq 5432 -and $ConfirmOwnerDb -cne 'YES-I-APPROVE') {
  throw 'للتنفيذ على قاعدة المالك عبر 5432، يلزم -ConfirmOwnerDb YES-I-APPROVE صراحةً.'
}

$pgBin = 'C:\Program Files\PostgreSQL\18\bin'
$psql = Join-Path $pgBin 'psql.exe'
if (-not (Test-Path $psql)) { throw "psql غير موجود: $psql" }
$backupScript = Join-Path $PSScriptRoot 'backup_postgres.ps1'
$backupRoot = Join-Path $PSScriptRoot '..\backups\postgres\fiscal_year_overlap'
$backupRunId = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), [guid]::NewGuid().ToString('N')
$backupRunDir = Join-Path $backupRoot $backupRunId
$powershell = Join-Path $PSHOME 'powershell.exe'
& $powershell -NoProfile -File $backupScript -Database $Database -DbHost $DbHost `
  -Port $Port -User $User -OutDir $backupRunDir -KeepDaily 3650 -KeepWeekly 520 -PgBin $pgBin
$backupExit = $LASTEXITCODE
if ($backupExit -ne 0) { throw "فشل backup_postgres.ps1 برمز $backupExit؛ أُوقف الترحيل." }

function Invoke-Psql([string]$Sql) {
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $psqlOutput = & $psql --host $DbHost --port $Port --username $User --dbname $Database `
      --no-password --set ON_ERROR_STOP=1 --tuples-only --no-align --command $Sql 2>&1
    $psqlExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($psqlExit -ne 0) { throw "psql failed: $($psqlOutput -join [Environment]::NewLine)" }
  return $psqlOutput
}

Write-Host ('قبل الترحيل ({0}:{1}/{2}):' -f $DbHost, $Port, $Database)
Invoke-Psql "SELECT 'years='||count(*)||'; visible='||count(*) FILTER (WHERE deleted_at IS NULL) FROM fiscal_years; SELECT 'journal_entries='||count(*) FROM journal_entries; SELECT 'accounts='||count(*) FROM accounts; SELECT id||'|'||name||'|'||start_date||'|'||end_date||'|'||COALESCE(deleted_at::text,'NULL') FROM fiscal_years WHERE id IN (1,$TargetId) ORDER BY id;" | ForEach-Object { Write-Host $_ }

$repairTransactionSql = @"
BEGIN;
DO `$repair`$
DECLARE
  fk RECORD;
  linked_count BIGINT;
  before_entries BIGINT;
  after_entries BIGINT;
  before_balances JSONB;
  after_balances JSONB;
  target_exists BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM fiscal_years WHERE id = $TargetId) INTO target_exists;
  IF NOT target_exists THEN RAISE EXCEPTION 'Fiscal year id % does not exist', $TargetId; END IF;
  SELECT count(*) INTO before_entries FROM journal_entries;
  SELECT COALESCE(jsonb_object_agg(account_id, balance ORDER BY account_id), '{}'::jsonb)
    INTO before_balances
    FROM (SELECT a.id AS account_id, COALESCE(sum(l.debit-l.credit),0) AS balance
          FROM accounts a LEFT JOIN journal_entry_lines l ON l.account_id=a.id
          GROUP BY a.id) balances;

  FOR fk IN
    SELECT tc.table_schema, tc.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name=kcu.constraint_name AND tc.constraint_schema=kcu.constraint_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name=tc.constraint_name AND ccu.constraint_schema=tc.constraint_schema
    WHERE tc.constraint_type='FOREIGN KEY' AND ccu.table_schema='public'
      AND ccu.table_name='fiscal_years' AND ccu.column_name='id'
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I=`$1', fk.table_schema, fk.table_name, fk.column_name)
      INTO linked_count USING $TargetId;
    RAISE NOTICE 'FK %.%.% -> id %: % row(s)', fk.table_schema, fk.table_name, fk.column_name, $TargetId, linked_count;
    IF linked_count > 0 THEN
      RAISE EXCEPTION 'Repair stopped: id % is referenced by %.%.% (% rows)',
        $TargetId, fk.table_schema, fk.table_name, fk.column_name, linked_count;
    END IF;
  END LOOP;

  FOR fk IN
    SELECT table_schema, table_name, column_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='fiscal_year_id'
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I=`$1', fk.table_schema, fk.table_name, fk.column_name)
      INTO linked_count USING $TargetId;
    RAISE NOTICE 'Column %.%.% -> id %: % row(s)', fk.table_schema, fk.table_name, fk.column_name, $TargetId, linked_count;
    IF linked_count > 0 THEN
      RAISE EXCEPTION 'Repair stopped: id % is referenced by %.%.% (% rows)',
        $TargetId, fk.table_schema, fk.table_name, fk.column_name, linked_count;
    END IF;
  END LOOP;

  UPDATE fiscal_years SET deleted_at=COALESCE(deleted_at, (extract(epoch from clock_timestamp()))::bigint),
                          is_current=false
   WHERE id=$TargetId AND deleted_at IS NULL;
  GET DIAGNOSTICS linked_count = ROW_COUNT;
  RAISE NOTICE 'disabled id %: % row(s) changed', $TargetId, linked_count;

  SELECT count(*) INTO after_entries FROM journal_entries;
  SELECT COALESCE(jsonb_object_agg(account_id, balance ORDER BY account_id), '{}'::jsonb)
    INTO after_balances
    FROM (SELECT a.id AS account_id, COALESCE(sum(l.debit-l.credit),0) AS balance
          FROM accounts a LEFT JOIN journal_entry_lines l ON l.account_id=a.id
          GROUP BY a.id) balances;
  IF before_entries <> after_entries OR before_balances IS DISTINCT FROM after_balances THEN
    RAISE EXCEPTION 'Financial invariant changed; aborting: entries % -> %, account balances equal=%',
      before_entries, after_entries, before_balances IS NOT DISTINCT FROM after_balances;
  END IF;
  RAISE NOTICE 'verified invariants: journal_entries % -> %, per-account balances unchanged', before_entries, after_entries;
END;
`$repair`$;
COMMIT;
"@
Invoke-Psql $repairTransactionSql | ForEach-Object { Write-Host $_ }
Write-Host 'بعد الترحيل:'
Invoke-Psql "SELECT 'years='||count(*)||'; visible='||count(*) FILTER (WHERE deleted_at IS NULL) FROM fiscal_years; SELECT 'journal_entries='||count(*) FROM journal_entries; SELECT id||'|'||name||'|'||COALESCE(deleted_at::text,'NULL')||'|'||is_current FROM fiscal_years WHERE id IN (1,$TargetId) ORDER BY id; SELECT count(*) AS periods FROM accounting_periods;" | ForEach-Object { Write-Host $_ }
