# Addendum-4 warehouse scenarios: W15 (Android 12+/14 Bluetooth, WH-015), W14 (count overlap/recount, WH-014),
# W30 (self-receive ban, WH-030). Dot-sourced by run_lab.ps1 AFTER wh_scenarios.ps1 (uses its helpers:
# Scan, Go-Shell, NavTab, Open-Docs-Tile, Enter-Qty, Tail, Pass, Api-Call, Get-Facts, Switch-User ...).
$script:WhPkgName = 'com.picpos.warehouse'
$script:Aapt2 = 'D:\dev-cache\android-sdk\build-tools\36.0.0\aapt2.exe'

function Bt-State {
  $d = (A shell dumpsys package $script:WhPkgName) -join "`n"
  if ($d -match 'android\.permission\.BLUETOOTH_CONNECT: granted=(true|false)') { return $Matches[1] }
  return 'not-listed'
}
# System permission dialog (com.android.permissioncontroller). The button ids vary between the first and a repeated request
# (permission_deny_button / permission_deny_and_dont_ask_again_button / permission_allow_*), and the label uses a typographic
# apostrophe (Don’t allow), so match by id prefix OR by the label with `.` for the apostrophe.
$script:PermAny = 'permission_(allow|deny)\w*button|^(Allow|Don.t allow|Deny)\|'
$script:PermDeny = 'permission_deny\w*button|^(Don.t allow|Deny)\|'
function Perm-Dialog { Find-Node $script:PermAny }
function Open-Printer-Settings([string]$barcode) {
  Go-Shell | Out-Null; Open-Docs-Tile 'الملصقات'
  Scan $barcode; Hide-Keyboard
  Tap-Node '^\|اختيار الطابعة' | Out-Null; Start-Sleep 3
}
function Deny-Dialog {   # taps "Don't allow" until the system dialog is gone; returns how many taps it took (the dialog once stayed up after one tap)
  $n = 0
  for ($i = 0; $i -lt 3; $i++) {
    if (-not (Wait-Node $script:PermAny 4)) { break }
    $dn = Find-Node $script:PermDeny
    if ($dn) { Log "Deny-Dialog: deny node id=$($dn.'resource-id') text=$($dn.text)"; $null = Save-Dump "w15-deny-dialog-$i" }
    if (-not (Tap-Node $script:PermDeny 5)) { Log 'Deny-Dialog: deny button not found by id/label' }
    $n++; Start-Sleep 3
  }
  return $n
}
function Ensure-App([string]$user = 'super1', [string]$pw = 'WhSuper#2026') {   # back in the warehouse app's shell, signed in as $user (PIN lock handled), whatever the previous scenario left on screen (even the Android home screen)
  if (Find-Node '^\|الإعدادات\s+علامة التبويب') { return $true }
  for ($try = 1; $try -le 3; $try++) {
    Log "Ensure-App: app shell not on screen, relaunching (try $try)"
    A shell am force-stop $script:WhPkgName | Out-Null; Start-Sleep 2; Launch $script:WhPkgName; Start-Sleep 6
    if (On-Onboarding) { if (Fresh-Pair-And-Login $user $pw) { return $true }; continue }
    if (On-Login) { Login $user $pw }
    $null = Handle-Pin
    if (Go-Shell) { return $true }
  }
  Log 'Ensure-App: could not get back to the app shell'; return $false
}
function Scan-Printers { Tap-Node '^\|البحث عن طابعات بلوتوث' | Out-Null; Start-Sleep 3 }

function Run-Wh15 {
  Log '===== W15: Android 14 Bluetooth (WH-015) ====='
  # static: the shipped APK manifest
  $apk = $Apk.wh
  $aapt = (& $script:Aapt2 dump permissions $apk 2>&1) -join "`n"
  Set-Content (Join-Path $script:RunDir 'w15-aapt2-permissions.txt') $aapt -Encoding utf8
  $okBtLegacy = ($aapt -match "name='android\.permission\.BLUETOOTH' maxSdkVersion='30'") -and ($aapt -match "name='android\.permission\.BLUETOOTH_ADMIN' maxSdkVersion='30'")
  $okConnect = ($aapt -match "name='android\.permission\.BLUETOOTH_CONNECT'")
  $noLoc = ($aapt -notmatch 'ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|ACCESS_BACKGROUND_LOCATION')
  Record 'W15.0a APK manifest (aapt2): BLUETOOTH/BLUETOOTH_ADMIN maxSdkVersion=30, BLUETOOTH_CONNECT present, NO location permission' (Pass ($okBtLegacy -and $okConnect -and $noLoc)) "legacyLimited=$okBtLegacy connect=$okConnect noLocation=$noLoc; $(($aapt -split "`n" | ? { $_ -match 'BLUETOOTH|LOCATION' }) -join ' ; '); file w15-aapt2-permissions.txt"

  $pre = Fresh-Pair-And-Login 'super1' 'WhSuper#2026'
  if (-not $pre) { Record 'W15 session' 'BLOCKED' (Screen-Text); return }
  $dump = (A shell dumpsys package $script:WhPkgName) -join "`n"
  Set-Content (Join-Path $script:RunDir 'w15-dumpsys-package.txt') $dump -Encoding utf8
  $noLocDev = ($dump -notmatch 'ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION')
  $noLegacyBt = ($dump -notmatch 'android\.permission\.BLUETOOTH(_ADMIN)?[:\s,]')
  $state0 = Bt-State
  Record 'W15.0b device (API 34) dumpsys: no location permission, legacy BLUETOOTH/ADMIN not requested, BLUETOOTH_CONNECT not granted at launch/sign-in' (Pass ($noLocDev -and $noLegacyBt -and ($state0 -eq 'false') -and -not (Perm-Dialog))) "api=$((A shell getprop ro.build.version.sdk) -join ''); noLocation=$noLocDev legacyBtAbsent=$noLegacyBt BLUETOOTH_CONNECT granted=$state0; permission dialog visible=$([bool](Perm-Dialog)); file w15-dumpsys-package.txt"

  # W15.1 no printer
  $bc = '6220000000110'
  Host-Do "product|n1|$bc|Lab Label Item|3|0|10|0|0" | Out-Null
  Go-Shell | Out-Null; Open-Docs-Tile 'الملصقات'
  Scan $bc; Hide-Keyboard
  Tap-Node '^\|طباعة$' | Out-Null; Start-Sleep 2
  $t = Screen-Text; $s = Shot 'w15-1-print-no-printer'; $cc = Crash-Check $script:WhPkgName
  $n = ([regex]::Matches($t, 'لا توجد طابعة متصلة')).Count
  Record 'W15.1 label print with no printer: honest "no printer connected", no crash, no permission prompt' (Pass (($n -ge 1) -and $cc.Alive -and -not $cc.Crashes -and -not (Perm-Dialog) -and ($t -notmatch 'طُبع'))) "no-printer text x$n; alive=$($cc.Alive) crashes=$($cc.Crashes); dialog=$([bool](Perm-Dialog)); BLUETOOTH_CONNECT=$(Bt-State); $s"

  # W15.2 permission flow at the moment Bluetooth is first needed (scan for paired printers)
  Tap-Node '^\|اختيار الطابعة' | Out-Null; Start-Sleep 3
  $ps = Screen-Text; $sPs = Shot 'w15-2-printer-settings'
  $beforeScan = Bt-State; $dlg0 = [bool](Perm-Dialog)
  Scan-Printers
  $d = Wait-Node $script:PermAny 10
  $dlgText = Screen-Text; $sD = Shot 'w15-2-permission-dialog'
  Record 'W15.2a BLUETOOTH_CONNECT is requested when the user asks for Bluetooth printers (not before)' (Pass (($beforeScan -eq 'false') -and (-not $dlg0) -and [bool]$d)) "before tap: granted=$beforeScan dialog=$dlg0; after tapping 'find Bluetooth printers': dialog shown=$([bool]$d): $(Tail $dlgText 200); $sD"
  $denyTaps1 = if ($d) { Deny-Dialog } else { 0 }
  $tDeny = Screen-Text; $sDeny = Shot 'w15-2-after-deny'
  Record 'W15.2b user denies -> UI says "permission denied" (not "no printer")' (Pass (($tDeny -match 'امنح التطبيق إذن البلوتوث|إذن البلوتوث مرفوض') -and ($tDeny -notmatch 'لا توجد طابعات بلوتوث'))) "granted=$(Bt-State); $(Tail $tDeny 220); $sDeny"
  A shell pm grant $script:WhPkgName android.permission.BLUETOOTH_CONNECT | Out-Null; Start-Sleep 2
  $g = Bt-State
  if (-not (Find-Node '^\|البحث عن طابعات بلوتوث' )) { Launch $script:WhPkgName; Start-Sleep 5; $null = Handle-Pin; Open-Printer-Settings $bc }
  Scan-Printers
  $tGr = Screen-Text; $sGr = Shot 'w15-2-after-grant'
  Record 'W15.2c after `pm grant`: no prompt, UI says "no paired printers"/"Bluetooth off", not "permission denied"' (Pass (($g -eq 'true') -and -not (Perm-Dialog) -and ($tGr -match 'لا توجد طابعات بلوتوث مقترنة|البلوتوث مُطفأ') -and ($tGr -notmatch 'امنح التطبيق إذن البلوتوث'))) "granted=$g; $(Tail $tGr 220); $sGr"
  A shell pm revoke $script:WhPkgName android.permission.BLUETOOTH_CONNECT | Out-Null; Start-Sleep 3
  $r = Bt-State
  Launch $script:WhPkgName; Start-Sleep 6; $null = Handle-Pin
  Open-Printer-Settings $bc
  Scan-Printers
  $d2 = Wait-Node $script:PermAny 10
  $denyTaps2 = if ($d2) { Deny-Dialog } else { 0 }
  $tRv = Screen-Text; $sRv = Shot 'w15-2-after-revoke'
  Record 'W15.2d after `pm revoke`: the app asks again; denial is reported honestly as permission' (Pass (($r -eq 'false') -and [bool]$d2 -and -not (Perm-Dialog) -and ($tRv -match 'امنح التطبيق إذن البلوتوث|إذن البلوتوث مرفوض'))) "state after revoke=$r; dialog shown=$([bool]$d2); deny taps=$denyTaps2; dialog still up=$([bool](Perm-Dialog)); BLUETOOTH_CONNECT=$(Bt-State); $(Tail $tRv 220); $sRv"
  $cc = Crash-Check $script:WhPkgName
  Record 'W15.3 no crash through the permission flow' (Pass (-not $cc.Crashes)) "alive=$($cc.Alive) crashes=$($cc.Crashes)"
}

function Run-Wh14 {
  Log '===== W14: count overlap / recount (WH-014) ====='
  Host-Do 'product|o1|6220000000134|Ovl Rice|5|0|10|0|0' | Out-Null
  Host-Do 'count|w14a|o1' | Out-Null   # older task
  Host-Do 'count|w14b|o1' | Out-Null   # newer task, same product, same warehouse
  $fx = Fixtures; $prodId = $fx.products.o1.id; $bc = '6220000000134'; $wh1 = $H.warehouses.B1
  $refA = $fx.counts.w14a.ref; $refB = $fx.counts.w14b.ref
  function Count-Pass([string]$user, [string]$ref, [string]$gid, [string]$qty, [string]$tag) {
    $e = Api-Call "w14-$tag-entries" $user 'POST' "/api/m1/wh/counts/$ref/entries" (@{ globalId = $gid; entries = @(@{ lineGlobalId = "$gid-line"; productId = $prodId; quantity = $qty }) } | ConvertTo-Json -Depth 5 -Compress) ''
    $s = Api-Call "w14-$tag-submit" $user 'POST' "/api/m1/wh/counts/$ref/submit" (@{ globalId = $gid } | ConvertTo-Json -Compress) ''
    return "$($e.status)/$($s.status)"
  }
  $cA = Count-Pass 'clerk1' $refA 'lab-w14-doc-a-0001' '10' 'a'
  $cB = Count-Pass 'clerk1' $refB 'lab-w14-doc-b-0001' '10' 'b'
  $f = Get-Facts 'w14-submitted'
  Record 'W14.0 fixtures: two overlapping tasks (same warehouse + product), both counted equal to system by clerk1' (Pass (($cA -eq '200/200') -and ($cB -eq '200/200'))) "task A=$refA entries/submit=$cA; task B=$refB $cB; stock=$(Qty $f $bc $wh1)"
  $a1 = Api-Call 'w14-approve-b-first' 'super1' 'POST' "/api/m1/wh/counts/$refB/approve" '{}' ''
  Record 'W14.1 approving the NEWER task while an OLDER overlapping task is open is refused (409 overlapping_count_task)' (Pass (($a1.status -eq 409) -and ($a1.body.error -eq 'overlapping_count_task'))) "=> $($a1.status) $($a1.body | ConvertTo-Json -Compress)"
  $a2 = Api-Call 'w14-approve-a' 'super1' 'POST' "/api/m1/wh/counts/$refA/approve" '{}' ''
  Record 'W14.2 the older task settles first (approve OK)' (Pass ($a2.status -eq 200)) "=> $($a2.status) $($a2.body | ConvertTo-Json -Compress)"
  $a3 = Api-Call 'w14-approve-b-stale' 'super1' 'POST' "/api/m1/wh/counts/$refB/approve" '{}' ''
  Record 'W14.3 the newer task, counted before the older one completed, is refused as stale (409 stale_overlap_count)' (Pass (($a3.status -eq 409) -and ($a3.body.error -eq 'stale_overlap_count'))) "=> $($a3.status) $($a3.body | ConvertTo-Json -Compress)"
  # UI: what does the supervisor SEE for that refusal? (the phone may be anywhere - Android home, other app - so relaunch + sign in first)
  $appOk = Ensure-App 'super1' 'WhSuper#2026'
  Go-Shell | Out-Null; Open-Docs-Tile 'الاعتمادات'
  $inbox = Screen-Text; $null = Save-Dump 'w14-ui-inbox'
  $row = Tap-Node '^\|جرد جاهز للاعتماد' 10; Start-Sleep 3
  $dlg = Screen-Text; $null = Save-Dump 'w14-ui-review-dialog'; $sDlg = Shot 'w14-ui-review-dialog'
  $tapped = Tap-Node '^\|اعتماد الجرد' 8
  # the refusal is a SnackBar (wh_widgets.dart:221 showFailure): poll briefly for it, then keep the first dump that has any refusal text
  $snack = ''
  for ($w = 0; $w -lt 8 -and -not $snack; $w++) {
    Start-Sleep -Milliseconds 700
    $cur = Screen-Text
    if ($cur -match 'حدث خطأ غير متوقع|Something went wrong|عدّ|أعد|تداخل|قديم|متقادم|هذا المعرّف|تغيّر المستند|لا يمكن|مرفوض|overlap|stale|recount') { $snack = $cur }
  }
  $quick = if ($snack) { $snack } else { Screen-Text }; $sU = Shot 'w14-ui-stale-refusal'; $null = Save-Dump 'w14-ui-stale-refusal'
  $generic = $quick -match 'حدث خطأ غير متوقع|Something went wrong'
  $told = ($quick -match 'تداخل|قديم|متقادم|عدّ ثانٍ|أعد العدّ|overlap|stale|recount') -and -not $generic
  $fH = Get-Facts 'w14-ui'
  $bTask = @(Doc-Of $fH 'count_submission' | ? { $_.ref_id -eq "$($fx.counts.w14b.taskId)" })
  $notPosted = (@($bTask | ? { $_.state -eq 'posted' }).Count -eq 0) -and ((Qty $fH $bc $wh1) -eq 10)
  Record 'W14.4a UI: approving the stale overlapping count is refused visibly (a refusal message, count NOT posted, stock unchanged, no crash)' (Pass ($appOk -and $row -and $tapped -and [bool]$snack -and $notPosted -and (Crash-Check $script:WhPkgName).Alive)) "app shell ok=$appOk; inbox row tapped=$row; approve tapped=$tapped; refusal text shown=$([bool]$snack): $(Tail $quick 260); host: task B docs=$(@($bTask | % { $_.state }) -join ','), stock=$(Qty $fH $bc $wh1); $sU"
  Record 'W14.4b UI: the supervisor is told WHY (overlap/stale/recount) rather than the generic error' (Pass $told) "told specific reason=$told; generic 'Something went wrong / حدث خطأ غير متوقع' shown=$generic. PRODUCT OBSERVATION when FAIL: wh_session.dart:14-24 kDomainCodes has no overlapping_count_task / stale_overlap_count, wh_session.dart:33-42 maps the 409 (ApiErrorKind.conflict) to 'unknown', strings.dart:342-346 falls back to err_unknown, approvals_page.dart:75-76 shows it through showFailure (wh_widgets.dart:221-227); $sU"  $rc = Api-Call 'w14-recount-b' 'super1' 'POST' "/api/m1/wh/counts/$refB/recount" '{"reason":"lab: overlap"}' ''
  $rc = Api-Call 'w14-recount-b' 'super1' 'POST' "/api/m1/wh/counts/$refB/recount" '{"reason":"lab: overlap"}' ''
  $same = Api-Call 'w14-retired-counter-again' 'clerk1' 'POST' "/api/m1/wh/counts/$refB/entries" (@{ globalId = 'lab-w14-doc-b-0002'; entries = @(@{ lineGlobalId = 'lab-w14-doc-b-0002-line'; productId = $prodId; quantity = '10' }) } | ConvertTo-Json -Depth 5 -Compress) ''
  $tk1 = Api-Call 'w14-tasks-clerk1' 'clerk1' 'GET' '/api/m1/wh/counts/tasks'
  $tk3 = Api-Call 'w14-tasks-clerk3' 'clerk3' 'GET' '/api/m1/wh/counts/tasks'
  $has1 = @($tk1.body.tasks | ? { $_.ref -eq $refB }).Count; $has3 = @($tk3.body.tasks | ? { $_.ref -eq $refB }).Count
  Record 'W14.5 manager sends the count back (recount); the retired counter cannot recount, another counter is offered the task' (Pass (($rc.status -eq 200) -and ($same.status -eq 409) -and ($has1 -eq 0) -and ($has3 -eq 1))) "recount => $($rc.status) $($rc.body | ConvertTo-Json -Compress); clerk1 count again => $($same.status) $($same.body.error); task in clerk1 list=$has1, in clerk3 list=$has3"
  $cB2 = Count-Pass 'clerk3' $refB 'lab-w14-doc-b-0003' '10' 'b2'
  $a4 = Api-Call 'w14-approve-b-final' 'super1' 'POST' "/api/m1/wh/counts/$refB/approve" '{}' ''
  $f = Get-Facts 'w14-done'
  $docsB = @(Doc-Of $f 'count_submission' | ? { $_.ref_id -eq "$($fx.counts.w14b.taskId)" })
  Record 'W14.6 recount by another counter, then approval succeeds; retired pass never posted; stock unchanged' (Pass (($cB2 -eq '200/200') -and ($a4.status -eq 200) -and (@($docsB | ? { $_.state -eq 'superseded' }).Count -eq 1) -and (@($docsB | ? { $_.state -eq 'posted' }).Count -eq 1) -and ((Qty $f $bc $wh1) -eq 10))) "clerk3 pass=$cB2; approve => $($a4.status) $($a4.body | ConvertTo-Json -Compress); task B docs states=$(@($docsB | % { $_.state }) -join ','); stock=$(Qty $f $bc $wh1)"
}

function Run-Wh30 {
  Log '===== W30: self-receive ban (WH-030) ====='
  Host-Do 'setting|wh_staged_transfers_enabled|true' | Out-Null
  Host-Do 'product|s1|6220000000127|Own Tea|4|0|20|0|0' | Out-Null
  $fx = Fixtures; $prodId = $fx.products.s1.id; $bc = '6220000000127'
  $wh1 = $H.warehouses.B1; $wh1b = $H.warehouses.B1b
  function New-Transfer([string]$tag) {
    $gid = "lab-w30-$tag-0001"
    $req = Api-Call "w30-$tag-request" 'store1' 'POST' '/api/m1/wh/transfers' (@{ globalId = $gid; fromWarehouseId = $wh1; toWarehouseId = $wh1b; lines = @(@{ lineGlobalId = "$gid-line"; productId = $prodId; quantity = '2' }) } | ConvertTo-Json -Depth 5 -Compress) ''
    $ap = Api-Call "w30-$tag-approve" 'super1' 'POST' "/api/m1/wh/transfers/$gid/approve" '{}' ''
    $di = Api-Call "w30-$tag-dispatch" 'super1' 'POST' "/api/m1/wh/transfers/$gid/dispatch" '{}' ''
    return [pscustomobject]@{ Gid = $gid; Line = "$gid-line"; Res = "$($req.status)/$($ap.status)/$($di.status)" }
  }
  $ta = New-Transfer 'a'
  $self = Api-Call 'w30-a-self-receive' 'super1' 'POST' "/api/m1/wh/transfers/$($ta.Gid)/receive" (@{ lines = @(@{ lineGlobalId = $ta.Line; received = '2' }) } | ConvertTo-Json -Depth 5 -Compress) ''
  $f = Get-Facts 'w30-self'
  $docA = @(Doc-Of $f 'transfer' | ? { $_.global_id -eq $ta.Gid })[0]
  Record 'W30.1 the dispatcher cannot receive his own transfer (host refusal, still in transit, destination stock untouched)' (Pass (($ta.Res -eq '200/200/200') -and ($self.status -in 403, 409) -and ($docA.state -eq 'in_transit') -and ((Qty $f $bc $wh1b) -in $null, 0))) "request/approve/dispatch=$($ta.Res); dispatcher receive => $($self.status) $($self.body | ConvertTo-Json -Compress); state=$($docA.state); stock B1b=$(Qty $f $bc $wh1b)"
  $other = Api-Call 'w30-a-second-user-receive' 'mgr1' 'POST' "/api/m1/wh/transfers/$($ta.Gid)/receive" (@{ lines = @(@{ lineGlobalId = $ta.Line; received = '2' }) } | ConvertTo-Json -Depth 5 -Compress) ''
  $f = Get-Facts 'w30-other'
  $docA = @(Doc-Of $f 'transfer' | ? { $_.global_id -eq $ta.Gid })[0]
  Record 'W30.2 a SECOND user can receive it (stock arrives once)' (Pass (($other.status -eq 200) -and ($docA.state -eq 'received') -and ((Qty $f $bc $wh1b) -eq 2))) "mgr1 receive => $($other.status) $($other.body | ConvertTo-Json -Compress); state=$($docA.state); stock B1b=$(Qty $f $bc $wh1b)"
  # UI: the dispatcher (super1, signed in on the phone) tries
  Ensure-App
  $tb = New-Transfer 'b'
  Go-Shell | Out-Null; Open-Docs-Tile 'التحويلات'
  $recvSheets = 0
  if (Tap-Node '^\|استلام$' 8) {
    if (Wait-Node 'الكمية المستلمة' 10) { Start-Sleep 1; if (Tap-Node '^\|تأكيد$') { $recvSheets++ } }
    if (Wait-Node 'منها تالف' 10) { Start-Sleep 1; if (Tap-Node '^\|تأكيد$') { $recvSheets++ } }
  }
  $q = Screen-Text; $sq = Shot 'w30-ui-self-receive'; Start-Sleep 4
  $ob = Outbox-Text; $so = Shot 'w30-ui-outbox'
  $f = Get-Facts 'w30-ui'
  $docB = @(Doc-Of $f 'transfer' | ? { $_.global_id -eq $tb.Gid })[0]
  $told = (($q + ' ' + $ob) -match 'لا يعتمد المستند من أنشأه|مرفوضة: [1-9]|لا يعتمد|رُفض')
  Record 'W30.3 UI: the dispatcher tries to receive on the phone -> not received, and the user sees a refusal' (Pass (($docB.state -eq 'in_transit') -and $told -and ($recvSheets -eq 2))) "sheets confirmed=$recvSheets; state=$($docB.state); screen: $(Tail $q 200); outbox: $(Tail $ob 260); $sq $so"
  $fin = Api-Call 'w30-b-second-user-receive' 'mgr1' 'POST' "/api/m1/wh/transfers/$($tb.Gid)/receive" (@{ lines = @(@{ lineGlobalId = $tb.Line; received = '2' }) } | ConvertTo-Json -Depth 5 -Compress) ''
  Record 'W30.4 the same transfer is then received by the second user' (Pass ($fin.status -eq 200)) "mgr1 receive => $($fin.status) $($fin.body | ConvertTo-Json -Compress)"
}

function Run-NewWarehouseScenarios {
  if (-not $SkipW15) { Run-Wh15 } elseif (-not $SkipW14 -or -not $SkipW30) { if (-not (Fresh-Pair-And-Login 'super1' 'WhSuper#2026')) { Record 'W14/W30 session' 'BLOCKED' (Screen-Text); return } }
  if (-not $SkipW14) { Run-Wh14 }
  if (-not $SkipW30) { Run-Wh30 }
}
