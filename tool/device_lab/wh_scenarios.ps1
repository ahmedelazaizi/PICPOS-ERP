# Warehouse W2-W5 scenarios of the device lab (dot-sourced by run_lab.ps1 after its helpers).
# Needs: lab_lib.ps1 (Host-Do, Get-Facts, Api-Call ...), run_lab.ps1 helpers (Fresh-Pair-And-Login, Login,
# Handle-Pin, On-Login, On-Onboarding, New-Code, Pair-Form), $H, $Pkg, $PIN.
# Each scenario creates its OWN fixtures on the host (unique product barcodes / PO / count task), so scenarios
# never depend on the state another one left; the staged-transfer setting is OFF until W3.2 turns it ON.

function NavTab([string]$name) { Tap-Node "^\|$name\s+علامة التبويب" | Out-Null; Start-Sleep 2 }
function Tap-Last([string]$pat) {
  $m = @(All-Nodes (Get-Dump) | Where-Object { (Node-Text $_) -match $pat })
  if (-not $m) { Log "TAPLAST FAIL /$pat/"; return $false }
  $c = Center $m[-1]; Log "tap-last /$pat/ at $($c -join ',')"; Tap-Xy $c[0] $c[1]; return $true
}
function Go-Shell {
  for ($i = 0; $i -lt 6; $i++) {
    if (Find-Node '^\|الإعدادات\s+علامة التبويب') { return $true }
    if (-not (Tap-Node '^\|رجوع$' 3)) { A shell input keyevent KEYCODE_BACK | Out-Null }
    Start-Sleep 1
  }
  return $false
}
function Scan([string]$code) { Type-Edit 0 $code | Out-Null; A shell input keyevent KEYCODE_ENTER | Out-Null; Start-Sleep 2 }
function Enter-Qty([string]$n) {
  Wait-Node '^\|تأكيد$' 10 | Out-Null
  Start-Sleep 1   # keypad bottom-sheet slide-in animation: taps during it can miss (see docs/testing/DEVICE-LAB.md)
  foreach ($ch in $n.ToCharArray()) { if ("$ch" -eq '.') { Tap-Last '^\|\.$' | Out-Null } else { Tap-Last "^\|$ch`$" | Out-Null } }
  Tap-Node '^\|تأكيد$' | Out-Null; Start-Sleep 2
}
function Open-Docs-Tile([string]$title) { Go-Shell | Out-Null; NavTab 'المستندات'; Tap-Node "^\|$title" | Out-Null; Start-Sleep 3 }
function Switch-User([string]$user, [string]$pw) {   # same paired phone: sign out in Settings, sign in as another user
  Go-Shell | Out-Null; NavTab 'الإعدادات'; Tap-Node '^\|تسجيل الخروج' | Out-Null; Start-Sleep 3
  if (-not (On-Login)) { Log "Switch-User: not on login screen"; return $false }
  Login $user $pw; $null = Handle-Pin
  return ((Screen-Text) -match 'مرحباً')
}
function Receive-Line([string]$barcode, [string]$qty) {
  Scan $barcode; Enter-Qty $qty
  Tap-Node '^\|إضافة$' | Out-Null; Start-Sleep 2
}
function Net-Off { A shell svc wifi disable | Out-Null; A shell svc data disable | Out-Null; A shell cmd connectivity airplane-mode enable | Out-Null; Start-Sleep 5 }
function Net-On { A shell cmd connectivity airplane-mode disable | Out-Null; A shell svc wifi enable | Out-Null; A shell svc data enable | Out-Null; Start-Sleep 10 }
function Send-Receipt([string]$orderNumber, $lines, [scriptblock]$BeforeSend = $null) {   # opens Documents > receive > PO, enters lines, presses send
  Open-Docs-Tile 'استلام أمر شراء'
  Tap-Node "^\|$orderNumber" | Out-Null; Start-Sleep 3
  foreach ($l in $lines) { Receive-Line $l[0] $l[1] }
  Hide-Keyboard
  $s = Shot "recv-$orderNumber-drafts"
  if ($BeforeSend) { & $BeforeSend }
  Tap-Node '^\|إرسال الاستلام' | Out-Null
  $quick = Screen-Text                  # snackbar is short-lived: dump right away
  $shot = Shot "recv-$orderNumber-after-send"
  Start-Sleep 4
  return [pscustomobject]@{ Quick = $quick; Shot = $shot; Drafts = $s }
}
function Outbox-Text { Go-Shell | Out-Null; NavTab 'قائمة الإرسال'; return (Screen-Text) }
function Pass($b) { if ($b) { 'PASS' } else { 'FAIL' } }
function Tail([string]$s, [int]$n = 300) { if ($s.Length -le $n) { $s } else { $s.Substring($s.Length - $n) } }
function Ev($f, [string]$action) { @($f.events | Where-Object { $_.action -eq $action }) }
function PoItemReceived($f, [int]$poId) { @(@($f.purchaseOrders | Where-Object { $_.id -eq $poId }).items | ForEach-Object { [double]$_.received_quantity }) }

function Run-WarehouseScenarios {
  $RUN = $script:RunDir
  Log '===== W: warehouse phases W2-W5 ====='
  # ---------- fixtures (host, real services) ----------
  Host-Do 'product|r1|6220000000011|Rcv Rice|5|0|0|0|0' | Out-Null
  Host-Do 'product|r2|6220000000028|Rcv Sugar|4|0|0|0|0' | Out-Null
  Host-Do 'po|w21|r1:10,r2:5' | Out-Null
  Host-Do 'po|w23|r1:10' | Out-Null
  Host-Do 'po|w22|r2:8' | Out-Null
  Host-Do 'product|c1|6220000000035|Cnt Oil|3|0|20|0|0' | Out-Null
  Host-Do 'product|c2|6220000000042|Cnt Tea|2|0|9|0|0' | Out-Null
  Host-Do 'count|w4|c1,c2' | Out-Null
  Host-Do 'product|t1|6220000000066|Trf Flour|10|0|10|0|0' | Out-Null
  Host-Do 'product|t2|6220000000073|Trf Salt|10|0|3|0|0' | Out-Null
  $fx = Fixtures
  $f0 = Get-Facts 'w-start'
  Record 'W0 fixtures + defaults' (Pass ($f0.settings.wh_staged_transfers_enabled -ne 'true')) "transfer setting default=$($f0.settings.wh_staged_transfers_enabled) (OFF); overage tolerance=$($f0.settings.wh_receipt_overage_pct); POs $($fx.pos.w21.orderNumber),$($fx.pos.w23.orderNumber),$($fx.pos.w22.orderNumber); count task ref=$($fx.counts.w4.ref); warehouses B1=$($H.warehouses.B1) B1b=$($H.warehouses.B1b)"
  $wh1 = $H.warehouses.B1; $wh1b = $H.warehouses.B1b
  $bcR1 = '6220000000011'; $bcR2 = '6220000000028'; $bcC1 = '6220000000035'; $bcC2 = '6220000000042'; $bcT1 = '6220000000066'; $bcT2 = '6220000000073'

  # ========== clerk1 session ==========
  $paired = $false
  for ($try = 1; $try -le 3 -and -not $paired; $try++) {
    Log "pairing attempt $try"; $paired = Fresh-Pair-And-Login 'clerk1' 'WhClerk#2026'
    if (-not $paired) { Shot "w-login-attempt-$try" | Out-Null; Save-Dump "w-login-attempt-$try" | Out-Null }
  }
  if (-not $paired) { Record 'W-LOGIN clerk1' 'BLOCKED' (Screen-Text); return }
  Record 'W-LOGIN clerk1' 'PASS' 'paired (TLS pin) + signed in as clerk1 on the NEW warehouse APK'

  # ---- W5.1a clerk: no approvals tile ----
  NavTab 'المستندات'; $docs = Screen-Text; $sA = Shot 'w51-clerk-docs'
  $api = Api-Call 'w51-clerk-approvals' 'clerk1' 'GET' '/api/m1/wh/approvals'
  Record 'W5.1a approvals inbox hidden from the clerk (UI + API)' (Pass (($docs -notmatch 'الاعتمادات') -and ($api.status -eq 403))) "docs tiles: $(Tail $docs 220); API GET approvals as clerk1 => $($api.status) $($api.body.error); $sA"

  # ---- W2.1 receive by barcode against the PO ----
  $po21 = $fx.pos.w21
  $r = Send-Receipt $po21.orderNumber @(@($bcR1, '6'), @($bcR2, '5'))
  $f = Get-Facts 'w21'
  $rec = @(Doc-Of $f 'po_receipt')
  $stockR1 = Qty $f $bcR1 $wh1
  $recvd = PoItemReceived $f $po21.id
  $okDoc = ($rec.Count -eq 1 -and $rec[0].state -eq 'submitted' -and $rec[0].created_by_name -eq 'clerk1' -and @($rec[0].lines).Count -eq 2)
  $okStock = (($null -eq $stockR1 -or $stockR1 -eq 0) -and (@($f.journal | Where-Object { $_.reference_type -like 'purchase*' }).Count -eq 0) -and (@($f.purchaseInvoices).Count -eq 0))
  Record 'W2.1a receive PO by barcode: receipt document exists (submitted, 2 lines)' (Pass $okDoc) "doc=$($rec[0].global_id) state=$($rec[0].state) lines=$(@($rec[0].lines | % { "$($_.product_id):$($_.qty_base)" }) -join ',') ; snackbar/screen right after send: $(Tail $r.Quick 160) ; $($r.Shot)"
  Record 'W2.1b design R-A: submit moves NO stock and posts NO ledger entry' (Pass $okStock) "B1 Rcv Rice stock after submit=$stockR1 (0/absent expected), purchase journal rows=$(@($f.journal | ? { $_.reference_type -like 'purchase*' }).Count), invoices=$(@($f.purchaseInvoices).Count); PO received_quantity (items, bumped at submit)=$($recvd -join ',')"
  $ob = Outbox-Text; $sO = Shot 'w21-outbox'
  # primary evidence = host events (one receipt_submit + one receipt_lines accepted); secondary = the outbox UI text:
  # op titles are Arabic ("استلام: إرسال", "استلام: الأصناف"), status chip "مقبولة", counter line "بانتظار الإرسال: N · مرفوضة: M".
  $hostOps = ((@(Ev $f 'receipt_submit').Count -eq 1) -and (@(Ev $f 'receipt_lines').Count -eq 1))
  $uiOps = ($ob -match 'استلام:\s*إرسال') -and ($ob -match 'استلام:\s*الأصناف') -and ([regex]::Matches($ob, 'مقبولة').Count -ge 2) -and ($ob -match 'بانتظار الإرسال:\D*0\D*مرفوضة:\D*0')
  Record 'W2.1c outbox shows both receipt ops accepted, nothing pending' (Pass ($hostOps -and $uiOps)) "host events receipt_submit=$(@(Ev $f 'receipt_submit').Count) receipt_lines=$(@(Ev $f 'receipt_lines').Count) (expected 1+1); UI: both op titles + 2x accepted chip + counter 0/0 = $uiOps; $(Tail $ob 260); $sO"

  # accountant converts (host side, real WhReceiptPosting.convert)
  $gid = $rec[0].global_id
  Host-Do "convert|$gid" | Out-Null
  $f = Get-Facts 'w21-convert'
  $recAfter = @(Doc-Of $f 'po_receipt')[0]
  $q1 = Qty $f $bcR1 $wh1; $q2 = Qty $f $bcR2 $wh1
  Record 'W2.4 accountant convert posts stock once (invoice, balances, PO closed)' (Pass (($recAfter.state -eq 'posted') -and ($q1 -eq 6) -and ($q2 -eq 5) -and (@($f.purchaseInvoices).Count -eq 1))) "doc state=$($recAfter.state) posted_ref=$($recAfter.posted_ref_id); stock Rice=$q1 Sugar=$q2; invoices=$(@($f.purchaseInvoices).Count)"
  Host-Do "convert|$gid" | Out-Null
  $c2 = Get-Content "$($env:LAB_DIR)\api-convert.json" -Raw
  $f = Get-Facts 'w21-convert2'
  Record 'W2.4b second convert refused (no double posting)' (Pass (($c2 -match 'invalid_transition') -and ((Qty $f $bcR1 $wh1) -eq 6) -and (@($f.purchaseInvoices).Count -eq 1))) "second convert => $c2 ; stock Rice still $(Qty $f $bcR1 $wh1)"

  # ---- W2.2 replay of the same commands ----
  $subEv = Ev $f 'receipt_submit'; $linEv = Ev $f 'receipt_lines'
  $k = $subEv[0].command_id
  $a1 = Api-Call 'w22-replay-submit' 'clerk1' 'POST' "/api/m1/wh/receipts/$gid/submit" '{}' $k
  $a2 = Api-Call 'w22-newkey-submit' 'clerk1' 'POST' "/api/m1/wh/receipts/$gid/submit" '{}' ''
  $f = Get-Facts 'w22'
  $recN = @(Doc-Of $f 'po_receipt').Count
  $evN = @(Ev $f 'receipt_submit').Count
  Record 'W2.2 replay of the SAME submit command id creates no duplicate' (Pass (($a1.status -eq 200) -and ($a1.body.replayed -eq $true) -and ($recN -eq 1) -and ($evN -eq 1) -and ((PoItemReceived $f $po21.id) -join ',') -eq ($recvd -join ','))) "replay => $($a1.status) replayed=$($a1.body.replayed); receipts=$recN submit-events=$evN; PO received unchanged=$((PoItemReceived $f $po21.id) -join ',')"
  Record 'W2.2b a NEW command id on an already-posted receipt is refused (no second effect)' (Pass (($a2.status -eq 409))) "new key submit => $($a2.status) $($a2.body.error) $($a2.body.state)"

  # ---- W2.3 over-receipt ----
  $po23 = $fx.pos.w23
  $r = Send-Receipt $po23.orderNumber @(,@($bcR1, '11'))
  $ob = Outbox-Text; $sO = Shot 'w23-outbox'
  $f = Get-Facts 'w23'
  $w23docs = @(Doc-Of $f 'po_receipt' | Where-Object { $_.ref_id -eq "$($po23.id)" })
  $w23recv = PoItemReceived $f $po23.id
  $okRefused = ($w23docs.Count -le 1) -and (@($w23docs | Where-Object { $_.state -ne 'draft' }).Count -eq 0) -and (($w23recv | Measure-Object -Sum).Sum -eq 0)
  Record 'W2.3a over-receipt (11 of 10) is refused by the host, nothing counted as received' (Pass $okRefused) "docs for PO: $($w23docs.Count) states=$(@($w23docs | % { $_.state }) -join ',') ; PO received=$($w23recv -join ',') ; outbox: $(Tail $ob 300) ; $sO"
  $shownRejected = ($ob -match 'مرفوضة: 1') -and ($ob -match 'الكمية تتجاوز')
  Record 'W2.3b the user is told the quantity was refused (outbox rejected + reason)' (Pass $shownRejected) "outbox text has 'مرفوضة: 1' and the over-receipt reason: $shownRejected"
  $misleading = ($r.Quick -match 'أُرسل الاستلام إلى المكتب')
  Record 'W2.3c receive screen does not claim success for a refused receipt' (Pass (-not $misleading)) "screen/snackbar right after send: '$(Tail $r.Quick 200)' ; success text shown=$misleading (suspect mobile_warehouse/lib/screens/receive_pages.dart:141 shows receiptSent whenever the drain completes, even when the server rejected the op) ; $($r.Shot)"

  # ---- W4.1 blind count (clerk1) ----
  NavTab 'بحث صنف'; Scan $bcC1; Hide-Keyboard; $lk = Screen-Text; $sL = Shot 'w41-lookup-blind'
  Open-Docs-Tile 'الجرد'; Tap-Node '^\|B1 Main WH' | Out-Null; Start-Sleep 3
  $cp = Screen-Text; $sC = Shot 'w41-count-page'
  $api1 = Api-Call 'w41-tasks' 'clerk1' 'GET' '/api/m1/wh/counts/tasks'
  $api2 = Api-Call 'w41-items' 'clerk1' 'GET' "/api/m1/wh/items?barcode=$bcC1"
  $api3 = Api-Call 'w41-review' 'clerk1' 'GET' "/api/m1/wh/counts/$($fx.counts.w4.ref)/review"
  $j1 = ($api1.body | ConvertTo-Json -Depth 8 -Compress); $j2 = ($api2.body | ConvertTo-Json -Depth 8 -Compress)
  $uiLeak = ($lk -match '(^|\D)20(\D|$)') -or ($cp -match 'المتوقع') -or ($cp -match '\|20(\s|$)')
  $apiLeak = ($j1 -match 'expected|variance|quantity|qty|onHand') -or ($j2 -match '"quantity"')
  $blindFlag = ($j2 -match '"blind":true') -or ($j2 -match '"blind":"True"')
  Record 'W4.1a counter UI never shows the expected quantity (lookup + count page)' (Pass ((-not $uiLeak) -and ($lk -match 'محجوبة'))) "lookup: $(Tail $lk 160) ; count page: $(Tail $cp 200) ; $sL $sC"
  Record 'W4.1b counter API responses carry no expected/variance/quantity (tasks DTO, items DTO; review 403)' (Pass ((-not $apiLeak) -and $blindFlag -and ($api3.status -eq 403))) "tasks=$($api1.status) leakKeys=$apiLeak ; items blind flag=$blindFlag ; review as counter => $($api3.status) $($api3.body.error)"

  # counter counts (variance on Cnt Oil: 18 vs 20)
  Tap-Node '^\|Cnt Oil' | Out-Null; Start-Sleep 2; Enter-Qty '18'
  Tap-Node '^\|Cnt Tea' | Out-Null; Start-Sleep 2; Enter-Qty '9'
  Hide-Keyboard
  $before = Shot 'w42-count-filled'
  Tap-Node '^\|إرسال الجرد' | Out-Null; Start-Sleep 5; $sS = Shot 'w42-count-sent'
  $f = Get-Facts 'w42-pass1'
  $cs = @(Doc-Of $f 'count_submission')
  Record 'W4.2a first count submitted (counter clerk1, variance recorded privately)' (Pass (($cs.Count -eq 1) -and ($cs[0].state -eq 'submitted'))) "count docs=$($cs.Count) state=$($cs[0].state) data=$($cs[0].data_json); stock Oil still $(Qty $f $bcC1 $wh1) (no adjustment yet); $sS"
  $ap1 = Api-Call 'w42-self-approve' 'clerk1' 'POST' "/api/m1/wh/counts/$($fx.counts.w4.ref)/approve" '{}' ''
  $ap2 = Api-Call 'w42-super-early-approve' 'super1' 'POST' "/api/m1/wh/counts/$($fx.counts.w4.ref)/approve" '{}' ''
  $f = Get-Facts 'w42-refusals'
  Record 'W4.2b the counter cannot approve his own count (refused, stock unchanged)' (Pass (($ap1.status -in 401, 403) -and ((Qty $f $bcC1 $wh1) -eq 20))) "clerk1 approve => $($ap1.status) $($ap1.body.error); stock Oil=$(Qty $f $bcC1 $wh1)"
  Record 'W4.2c supervisor cannot approve while a recount by another counter is required' (Pass (($ap2.status -eq 409) -and ($ap2.body.error -eq 'recount_required') -and ((Qty $f $bcC1 $wh1) -eq 20))) "super1 approve before recount => $($ap2.status) $($ap2.body.error)"

  # ---- W5.2 labels / printing honesty (clerk1 has inventory_view) ----
  Go-Shell | Out-Null; Open-Docs-Tile 'الملصقات'
  Scan $bcR1; Hide-Keyboard; $lab = Screen-Text
  Tap-Node '^\|طباعة$' | Out-Null; Start-Sleep 2; $labAfter = Screen-Text; $sP = Shot 'w52-label-print'
  $cnt = ([regex]::Matches($labAfter, 'لا توجد طابعة متصلة')).Count
  Tap-Node '^\|اختيار الطابعة' | Out-Null; Start-Sleep 3; $ps = Screen-Text; $sPs = Shot 'w52-printer-settings'
  $f = Get-Facts 'w52'
  Record 'W5.2 label print with no printer: honest "no printer connected", no fake success, no stock effect' (Pass (($cnt -ge 2) -and ($labAfter -notmatch 'طُبع الملصق')) ) "before print: $(Tail $lab 140) ; after print mentions 'no printer' x$cnt, 'printed' text present=$($labAfter -match 'طُبع'); printer settings: $(Tail $ps 200); stock Rice unchanged=$(Qty $f $bcR1 $wh1); $sP $sPs"

  # ========== clerk3: second counter ==========
  if (Switch-User 'clerk3' 'WhClerk3#2026') {
    Open-Docs-Tile 'الجرد'; Tap-Node '^\|B1 Main WH' | Out-Null; Start-Sleep 3
    Tap-Node '^\|Cnt Oil' | Out-Null; Start-Sleep 2; Enter-Qty '18'
    Tap-Node '^\|Cnt Tea' | Out-Null; Start-Sleep 2; Enter-Qty '9'
    Hide-Keyboard; Tap-Node '^\|إرسال الجرد' | Out-Null; Start-Sleep 5; $sS = Shot 'w42-recount-sent'
    $f = Get-Facts 'w42-pass2'
    $cs = @(Doc-Of $f 'count_submission')
    Record 'W4.2d recount by a DIFFERENT counter (clerk3) accepted' (Pass (($cs.Count -eq 2) -and (@($cs | ? { $_.state -eq 'submitted' }).Count -eq 2))) "count docs=$($cs.Count) creators=$(@($cs | % { $_.created_by_name }) -join ',') ; $sS"
  } else { Record 'W4.2d recount by a different counter' 'BLOCKED' 'could not sign in as clerk3' }

  # ========== store1: transfers, setting OFF then ON ==========
  if (Switch-User 'store1' 'WhStore#2026') {
    $api = Api-Call 'w31-off-request' 'store1' 'POST' '/api/m1/wh/transfers' (@{ globalId = 'lab-transfer-off-0001'; fromWarehouseId = $wh1; toWarehouseId = $wh1b; lines = @(@{ lineGlobalId = 'lab-tline-off-0001'; productId = $fx.products.t1.id; quantity = '1' }) } | ConvertTo-Json -Depth 5 -Compress) ''
    Open-Docs-Tile 'التحويلات'; $tt = Screen-Text; $sT = Shot 'w31-transfers-off'
    Tap-Node '^\|طلب تحويل' 3 | Out-Null; Start-Sleep 2; $tt2 = Screen-Text; $sT2 = Shot 'w31-new-transfer-off'
    $f = Get-Facts 'w31'
    Record 'W3.1 transfer with the setting OFF is refused honestly (API 409 + UI list message, no document)' (Pass (($api.status -eq 409) -and ($api.body.error -eq 'staged_transfers_disabled') -and (@(Doc-Of $f 'transfer').Count -eq 0))) "API request => $($api.status) $($api.body.error); transfers screen: $(Tail $tt 220); new-transfer screen: $(Tail $tt2 160); transfer docs on host=$(@(Doc-Of $f 'transfer').Count); $sT $sT2"
    Host-Do 'setting|wh_staged_transfers_enabled|true' | Out-Null
    # request t1 (4 of 10) and t2 (8 of 3 - more than available)
    foreach ($t in @(@('Trf Flour', $bcT1, '4'), @('Trf Salt', $bcT2, '8'))) {
      Go-Shell | Out-Null; Open-Docs-Tile 'التحويلات'
      Tap-Node '^\|طلب تحويل' | Out-Null; Start-Sleep 2
      Tap-Node '^\|من مخزن' | Out-Null; Start-Sleep 2; Tap-Last '^\|B1 Main WH$' | Out-Null; Start-Sleep 1
      Tap-Node '^\|إلى مخزن' | Out-Null; Start-Sleep 2; Tap-Last '^\|B1 Second WH$' | Out-Null; Start-Sleep 1
      Scan $t[1]; Enter-Qty $t[2]; Hide-Keyboard
      Tap-Node '^\|إرسال الطلب' | Out-Null; Start-Sleep 5; Shot "w32-request-$($t[0] -replace ' ','-')" | Out-Null
    }
    $f = Get-Facts 'w32-requested'
    $tr = @(Doc-Of $f 'transfer')
    Record 'W3.2a store1 requests two transfers (setting now ON)' (Pass (($tr.Count -eq 2) -and (@($tr | ? { $_.state -eq 'requested' }).Count -eq 2))) "transfer docs=$($tr.Count) states=$(@($tr | % { $_.state }) -join ',')"
    $tg = $tr[-1].global_id
    $apiSelf = Api-Call 'w32-store-self-approve' 'store1' 'POST' "/api/m1/wh/transfers/$tg/approve" '{}' ''
    Record 'W3.2b the requester (no approve right) cannot approve his own transfer' (Pass ($apiSelf.status -in 403)) "store1 approve => $($apiSelf.status) $($apiSelf.body.error)"
    $apiInbox = Api-Call 'w51-store-approvals' 'store1' 'GET' '/api/m1/wh/approvals'
    Go-Shell | Out-Null; NavTab 'المستندات'; $stDocs = Screen-Text
    Record 'W5.1b approvals inbox hidden from the storekeeper (UI tile + API)' (Pass (($stDocs -notmatch 'الاعتمادات') -and ($apiInbox.status -eq 403))) "storekeeper docs tiles: $(Tail $stDocs 200); API approvals => $($apiInbox.status) $($apiInbox.body.error)"
  } else { Record 'W3 store1 session' 'BLOCKED' 'could not sign in as store1' }

  # ========== super1: approvals inbox, transfer dispatch/receive, count approval ==========
  if (Switch-User 'super1' 'WhSuper#2026') {
    Open-Docs-Tile 'الاعتمادات'; $inbox = Screen-Text; $sI = Shot 'w51-super-inbox'
    $apiInbox = Api-Call 'w51-super-approvals' 'super1' 'GET' '/api/m1/wh/approvals'
    $types = @($apiInbox.body.approvals | % { $_.type }) -join ','
    Record 'W5.1c approvals inbox visible to the supervisor (2 transfer requests + the count)' (Pass (($inbox -match 'طلب تحويل') -and ($inbox -match 'جرد جاهز للاعتماد') -and ($apiInbox.status -eq 200))) "API types=$types count=$($apiInbox.body.count); UI: $(Tail $inbox 220); $sI"
    # approve both transfers from the inbox
    for ($i = 0; $i -lt 2; $i++) {
      Go-Shell | Out-Null; Open-Docs-Tile 'الاعتمادات'
      if (Tap-Node '^\|طلب تحويل' 6) { Start-Sleep 2; Tap-Node '^\|اعتماد$' | Out-Null; Start-Sleep 3 }
    }
    $f = Get-Facts 'w32-approved'
    $tr = @(Doc-Of $f 'transfer')
    Record 'W3.2c supervisor (different user) approves both transfer requests from the inbox' (Pass (@($tr | ? { $_.state -eq 'approved' }).Count -eq 2)) "states=$(@($tr | % { "$($_.created_by_name)->$($_.approved_by_name):$($_.state)" }) -join ' ; ')"
    # dispatch + receive via Transfers screen
    Go-Shell | Out-Null; Open-Docs-Tile 'التحويلات'
    $tx = Screen-Text; Shot 'w32-transfers-approved' | Out-Null
    Tap-Last '^\|إرسال البضاعة' | Out-Null; Start-Sleep 5     # oldest row = Trf Flour (list is newest first)
    Tap-Last '^\|إرسال البضاعة' | Out-Null; Start-Sleep 5     # the remaining one = Trf Salt (8 of 3)
    $sD = Shot 'w32-after-dispatch'
    $f = Get-Facts 'w32-dispatched'
    $tr = @(Doc-Of $f 'transfer')
    $g1 = $tr | ? { @($_.lines)[0].product_id -eq $fx.products.t1.id }
    $g2 = $tr | ? { @($_.lines)[0].product_id -eq $fx.products.t2.id }
    $s1a = Qty $f $bcT1 $wh1; $s1b = Qty $f $bcT1 $wh1b; $s2a = Qty $f $bcT2 $wh1
    $git = [double]$f.goodsInTransitBalance
    $okDisp = ($g1.state -eq 'in_transit') -and ($s1a -eq 6) -and (($null -eq $s1b) -or ($s1b -eq 0)) -and ($git -eq 40)
    Record 'W3.2d dispatch reduces source stock and books the in-transit entry' (Pass $okDisp) "Flour: B1 main=$s1a (10-4), second=$s1b, goods_in_transit balance=$git (4 x cost 10 = 40), doc state=$($g1.state); journal rows=$(@($f.journal | ? { $_.reference_type -eq 'wh_transfer_out' }).Count); $sD"
    Record 'W3.3 transfer larger than available (8 of 3) is refused at dispatch, no negative stock' (Pass (($g2.state -eq 'approved') -and ($s2a -eq 3))) "Salt doc state=$($g2.state) (stays approved), B1 main stock=$s2a (unchanged 3); outbox: $(Tail (Outbox-Text) 260)"
    Go-Shell | Out-Null; Open-Docs-Tile 'التحويلات'
    # The receive action opens TWO keypad sheets per line (mobile_warehouse/lib/screens/transfer_pages.dart:67 received qty,
    # :71 damaged qty); each is pre-filled (dispatched 4 / 0) and needs its own "تأكيد". Wait for each title (sheet animation).
    $recvSheets = 0
    if (Tap-Node '^\|استلام$' 6) {
      if (Wait-Node 'الكمية المستلمة' 10) { Start-Sleep 1; if (Tap-Node '^\|تأكيد$') { $recvSheets++ } }
      if (Wait-Node 'منها تالف' 10) { Start-Sleep 1; if (Tap-Node '^\|تأكيد$') { $recvSheets++ } }
      Start-Sleep 5
    }
    Log "transfer receive: confirmed $recvSheets keypad sheet(s)"
    $sR = Shot 'w32-after-receive'
    $f = Get-Facts 'w32-received'
    $tr = @(Doc-Of $f 'transfer'); $g1 = $tr | ? { @($_.lines)[0].product_id -eq $fx.products.t1.id }
    $s1a = Qty $f $bcT1 $wh1; $s1b = Qty $f $bcT1 $wh1b; $git = [double]$f.goodsInTransitBalance
    Record 'W3.2e receive at destination completes it: stock conserved, in-transit cleared' (Pass (($g1.state -eq 'received') -and ($s1a -eq 6) -and ($s1b -eq 4) -and ($git -eq 0))) "state=$($g1.state); Flour main=$s1a second=$s1b (sum $($s1a + $s1b) of 10); goods_in_transit=$git; keypad sheets confirmed=$recvSheets (2 expected); $sR"
    # never double: replay dispatch/receive command ids and fresh ids
    $dEv = (Ev $f 'transfer:dispatch')[0]; $rEv = (Ev $f 'transfer:receive')[0]
    $rp1 = Api-Call 'w32-replay-dispatch' 'super1' 'POST' "/api/m1/wh/transfers/$($g1.global_id)/dispatch" '{}' $dEv.command_id
    $rp2 = Api-Call 'w32-newkey-dispatch' 'super1' 'POST' "/api/m1/wh/transfers/$($g1.global_id)/dispatch" '{}' ''
    $rp3 = Api-Call 'w32-newkey-receive' 'super1' 'POST' "/api/m1/wh/transfers/$($g1.global_id)/receive" (@{ lines = @(@{ lineGlobalId = (@($g1.lines)[0].line_global_id); received = '4' }) } | ConvertTo-Json -Depth 5 -Compress) ''
    $f = Get-Facts 'w32-doubles'
    Record 'W3.2f never double: replayed command ids answer from the log, fresh dispatch/receive refused, stock unchanged' (Pass (($rp1.body.replayed -eq $true) -and ($rp2.status -eq 409) -and ($rp3.status -eq 409) -and ((Qty $f $bcT1 $wh1) -eq 6) -and ((Qty $f $bcT1 $wh1b) -eq 4) -and ([double]$f.goodsInTransitBalance -eq 0))) "replay dispatch => $($rp1.status) replayed=$($rp1.body.replayed); new-key dispatch => $($rp2.status) $($rp2.body.error); new-key receive => $($rp3.status) $($rp3.body.error); stock $((Qty $f $bcT1 $wh1))/$((Qty $f $bcT1 $wh1b)); GIT=$($f.goodsInTransitBalance)"

    # ---- W4.2 supervisor approves the count (different user from both counters) ----
    Go-Shell | Out-Null; Open-Docs-Tile 'الاعتمادات'
    $okRow = Tap-Node '^\|جرد جاهز للاعتماد' 8; Start-Sleep 3
    $rv = Screen-Text; $sV = Shot 'w42-review-dialog'
    Tap-Node '^\|اعتماد الجرد' | Out-Null; Start-Sleep 5; $sA2 = Shot 'w42-after-approve'
    $f = Get-Facts 'w42-approved'
    $cs = @(Doc-Of $f 'count_submission')
    $oil = Qty $f $bcC1 $wh1
    $adjMoves = @($f.stockMovements | Where-Object { $_.reference_type -like 'cycle*' -or $_.type -like '*count*' -or $_.type -like 'adjust*' })
    Record 'W4.2e supervisor (not a counter) approves in the inbox -> adjustment posted once' (Pass (($oil -eq 18) -and (@($cs | ? { $_.state -eq 'posted' }).Count -eq 2))) "review dialog: $(Tail $rv 260); Oil stock 20 -> $oil; count docs states=$(@($cs | % { $_.state }) -join ','); approved_by=$($cs[0].approved_by_name); stock movements (adjust/count)=$($adjMoves.Count); $sV $sA2"
    $again = Api-Call 'w42-second-approve' 'super1' 'POST' "/api/m1/wh/counts/$($fx.counts.w4.ref)/approve" '{}' ''
    $f = Get-Facts 'w42-after-second'
    Record 'W4.2f a second approval does not post again' (Pass (($again.status -eq 409) -and ((Qty $f $bcC1 $wh1) -eq 18))) "second approve => $($again.status) $($again.body.error); Oil stock=$(Qty $f $bcC1 $wh1)"
  } else { Record 'W3/W4 super1 session' 'BLOCKED' 'could not sign in as super1' }

  # ========== manager / accountant personas ==========
  if (Switch-User 'mgr1' 'WhMgr#2026') {
    NavTab 'المستندات'; $md = Screen-Text; $sM = Shot 'w51-manager-docs'
    Record 'W5.1d approvals inbox visible to the stock manager' (Pass ($md -match 'الاعتمادات')) "$(Tail $md 220); $sM"
  } else { Record 'W5.1d approvals inbox visible to the stock manager' 'BLOCKED' 'could not sign in as mgr1' }
  Go-Shell | Out-Null; NavTab 'الإعدادات'; Tap-Node '^\|تسجيل الخروج' | Out-Null; Start-Sleep 3
  Login 'acct1' 'WhAcct#2026'; $at = Screen-Text; $sAc = Shot 'w51-accountant-login'
  Record 'W5.1e accountant cannot use the warehouse app (login refused, no inbox)' (Pass ((On-Login) -and ($at -match 'صلاحية'))) "$(Tail $at 200); $sAc"

  # ========== W5.3 offline outbox (clerk1) ==========
  Login 'clerk1' 'WhClerk#2026'; $null = Handle-Pin
  $po53 = $null; Host-Do 'po|w53|r2:8' | Out-Null; $po53 = (Fixtures).pos.w53
  # (the PO page is opened online; the network is cut right before the send button)
  $r = Send-Receipt $po53.orderNumber @(,@($bcR2, '3')) { Net-Off }
  # PO list needs the office; if the list was loaded before going offline this works. Otherwise record the limit.
  $ob = Outbox-Text; $sO = Shot 'w53-outbox-offline'
  $f = Get-Facts 'w53-offline'
  $docsOff = @(Doc-Of $f 'po_receipt' | ? { $_.ref_id -eq "$($po53.id)" }).Count
  # primary = host has no document; secondary = outbox UI: the two receipt ops with "بانتظار الإرسال" chips + counter pending >= 2
  $uiQueued = ($ob -match 'استلام:\s*إرسال') -and ($ob -match 'استلام:\s*الأصناف') -and ($ob -match 'بانتظار الإرسال:\D*[2-9]')
  Record 'W5.3a offline: receipt is queued in the outbox, host has nothing yet' (Pass (($docsOff -eq 0) -and $uiQueued)) "host docs for PO=$docsOff (0 expected); UI shows both queued receipt ops + pending counter>=2 = $uiQueued (offline banner present=$($ob -match 'لا اتصال بالمكتب')); outbox: $(Tail $ob 300); screen after send: $(Tail $r.Quick 160); $sO"
  A shell am force-stop $Pkg.wh | Out-Null; Start-Sleep 2; Launch $Pkg.wh; Start-Sleep 6; $null = Handle-Pin
  $ob2 = Outbox-Text; $sO2 = Shot 'w53-outbox-after-relaunch'
  $fRel = Get-Facts 'w53-relaunch'
  $docsRel = @(Doc-Of $fRel 'po_receipt' | ? { $_.ref_id -eq "$($po53.id)" }).Count
  $uiRel = ($ob2 -match 'استلام:\s*إرسال') -and ($ob2 -match 'استلام:\s*الأصناف') -and ($ob2 -match 'بانتظار الإرسال:\D*[2-9]')
  Record 'W5.3b queue survives app relaunch (encrypted store)' (Pass (($docsRel -eq 0) -and $uiRel)) "after force-stop + relaunch (still offline): host docs for PO=$docsRel (0 expected, nothing lost/leaked), UI shows the same queued receipt ops + pending>=2 = $uiRel; $(Tail $ob2 260); $sO2"
  Net-On
  Tap-Node '^\|أرسل الآن' | Out-Null; Start-Sleep 6
  $ob3 = Screen-Text; $sO3 = Shot 'w53-outbox-replayed'
  $f = Get-Facts 'w53-online'
  $d53 = @(Doc-Of $f 'po_receipt' | ? { $_.ref_id -eq "$($po53.id)" })
  Record 'W5.3c network back: the document replays exactly once and the app shows it' (Pass (($d53.Count -eq 1) -and ($d53[0].state -eq 'submitted') -and ($ob3 -match 'مقبولة'))) "host docs for PO=$($d53.Count) state=$($d53[0].state); outbox: $(Tail $ob3 260); $sO3"
  Tap-Node '^\|أرسل الآن' | Out-Null; Start-Sleep 4
  $f = Get-Facts 'w53-second-drain'
  $d53b = @(Doc-Of $f 'po_receipt' | ? { $_.ref_id -eq "$($po53.id)" })
  $ev53 = @(Ev $f 'receipt_submit' | ? { $_.doc_id -eq $d53[0].id }).Count
  Record 'W5.3d second replay creates no duplicate' (Pass (($d53b.Count -eq 1) -and ($ev53 -eq 1) -and ((PoItemReceived $f $po53.id) -join ',') -eq '3')) "docs=$($d53b.Count) submit events=$ev53 PO received=$((PoItemReceived $f $po53.id) -join ',')"

  # ========== W5.4 revoked device mid-outbox ==========
  Host-Do 'po|w54|r2:8' | Out-Null; $po54 = (Fixtures).pos.w54
  # (offline again, same technique)
  $r = Send-Receipt $po54.orderNumber @(,@($bcR2, '2')) { Net-Off }
  $obq = Outbox-Text
  Host-Do 'revoke-all' | Out-Null
  Net-On
  Go-Shell | Out-Null; NavTab 'قائمة الإرسال'; Tap-Node '^\|أرسل الآن' | Out-Null; Start-Sleep 5
  $o1 = Screen-Text; $s1 = Shot 'w54-after-send-now'
  NavTab 'الرئيسية'; Tap-Node '^\|تحديث' 5 | Out-Null; Start-Sleep 5
  $o2 = Screen-Text; $s2 = Shot 'w54-after-home-refresh'
  $f = Get-Facts 'w54'
  $d54 = @(Doc-Of $f 'po_receipt' | ? { $_.ref_id -eq "$($po54.id)" }).Count
  $told = ($o1 -match 'أُلغي ربط|ألغي ربط') -or ($o2 -match 'أُلغي ربط|ألغي ربط')
  $wiped = (On-Onboarding)
  Record 'W5.4a revoked device: queued receipt is NOT replayed (no document on the host)' (Pass ($d54 -eq 0)) "host docs for PO=$d54; queue before: $(Tail $obq 200); after send-now: $(Tail $o1 200); after refresh: $(Tail $o2 200); $s1 $s2"
  Record 'W5.4b the user is told the phone was unpaired (and returns to pairing)' (Pass ($told -and $wiped)) "told='unpaired' message seen=$told; back on pairing screen=$wiped (suspect mobile_warehouse/lib/sync/wh_outbox.dart:101 rethrows deviceRevoked without wiping/telling; wipe only happens on the next session refresh wh_session.dart:170)"

  # ---------- final device-side crash check for the warehouse app ----------
  $cc = Crash-Check $Pkg.wh
  Record 'W-CRASH warehouse app alive / no crash buffer entries during W scenarios' (Pass ((-not $cc.Crashes))) "alive=$($cc.Alive) crashes=$($cc.Crashes)"
}
