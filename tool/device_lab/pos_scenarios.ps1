# Cashier (mobile_pos, kind=pos) scenarios C1-C5 of the device lab (dot-sourced by run_lab.ps1 after its helpers).
# Needs lab_lib.ps1 + the run_lab.ps1 helpers (Edit-Has, New-Code, Handle-Pin is NOT used: the cashier app has no PIN),
# $H, $Pkg. Host side: `issue B1 pos`, `posapi`, `legacy`, `legacyfacts`, `setting`, `revoke-all`.

function Pos-On-Login { $s = Screen-Text; ($s -match 'تسجيل دخول الكاشير|Cashier sign-in') -and ($s -match 'إلغاء ربط هذا الجهاز|Unpair this tablet') }
function Pos-On-Onboarding { $s = Screen-Text; ($s -match 'ربط جهاز الكاشير|Pair this cashier tablet') -and ($s -match 'أو أدخل الرمز يدوياً|Or enter the code manually') }
function Pos-In-Shell { $s = Screen-Text; ($s -match 'المعلّقة|Held') -and ($s -match 'الوردية|Shift') -and -not ($s -match 'تسجيل دخول الكاشير|Cashier sign-in') }
function Pos-Pair-Form([string]$addr, [string]$code, [string]$fp) {
  $vals = @($addr, $code, $fp)
  for ($round = 0; $round -lt 3; $round++) {
    for ($i = 0; $i -lt 3; $i++) { if (-not (Edit-Has $i $vals[$i])) { Type-Edit $i $vals[$i] | Out-Null } }
    if ((Edit-Has 0 $vals[0]) -and (Edit-Has 1 ($vals[1].ToUpper())) -and (Edit-Has 2 $vals[2])) { break }
    if ((Edit-Has 0 $vals[0]) -and (Edit-Has 1 $vals[1]) -and (Edit-Has 2 $vals[2])) { break }
    Log "Pos-Pair-Form: a field is still empty, retyping (round $round)"
  }
  Hide-Keyboard; Start-Sleep 3
  if (-not (Tap-Node '^\|ربط$' 25)) {
    $e = @(All-Nodes (Get-Dump) | Where-Object { $_.class -eq 'android.widget.EditText' })
    if ($e.Count -ge 3 -and $e[2].bounds -match '\[\d+,\d+\]\[\d+,(\d+)\]') { Log 'Pos-Pair-Form fallback tap by geometry'; Tap-Xy 540 ([int]$Matches[1] + 120) }
  }
  for ($w = 0; $w -lt 10; $w++) { Start-Sleep 2; if (Pos-On-Login) { break } }
}
function Pos-Login([string]$u, [string]$p) {
  Type-Edit 0 $u | Out-Null; Type-Edit 1 $p | Out-Null; Hide-Keyboard
  Tap-Node '^\|دخول$' | Out-Null; Start-Sleep 6
}
function Pos-Fresh-Pair([string]$branch = 'B1') {
  A shell pm clear $Pkg.pos | Out-Null; Launch $Pkg.pos; Start-Sleep 5
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    Cmd-Host "issue $branch pos"; Start-Sleep 3
    $code = @($(Host-Json).codes)[-1].code
    Pos-Pair-Form $H.address $code $H.fingerprint
    if (Pos-On-Login) { return $code }
    if ($attempt -eq 1) { A shell pm clear $Pkg.pos | Out-Null; Launch $Pkg.pos; Start-Sleep 5 }
  }
  return $null
}
function Pos-Call([string]$Label, [string]$User, [string]$Method, [string]$Path, [string]$Body = '', [string]$Key = '') {
  $r = Host-Do "posapi|$Label|$User|$Method|$Path|$Body|$Key"
  $f = Join-Path $script:LabDir "api-$Label.json"
  if (-not (Test-Path $f)) { return $null }
  Copy-Item $f (Join-Path $script:RunDir "api-$Label.json") -Force
  return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Legacy-Call([string]$Label, [string]$Method, [string]$Path, [string]$Dev = 'lab-old-phone') {
  Host-Do "legacy|$Label|$Method|$Path|$Dev" | Out-Null
  $f = Join-Path $script:LabDir "api-$Label.json"
  if (-not (Test-Path $f)) { return $null }
  Copy-Item $f (Join-Path $script:RunDir "api-$Label.json") -Force
  return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Legacy-Facts([string]$Name) {
  Host-Do "legacyfacts|$Name" | Out-Null
  $f = Join-Path $script:LabDir "facts-$Name.json"
  if (-not (Test-Path $f)) { return $null }
  Copy-Item $f (Join-Path $script:RunDir "facts-$Name.json") -Force
  return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Run-CashierScenarios {
  Log '===== C: cashier (mobile_pos, kind=pos) ====='
  # ---------- C1 pairing (TLS pin) ----------
  A shell pm clear $Pkg.pos | Out-Null; A shell input keyevent KEYCODE_WAKEUP | Out-Null; Launch $Pkg.pos; Start-Sleep 6
  $s = Shot 'c1-launch'; $cc = Crash-Check $Pkg.pos
  Record 'C1.0 cashier launch: unpaired, pairing screen with manual entry enabled' (Pass ($cc.Alive -and -not $cc.Crashes -and (Pos-On-Onboarding))) "alive=$($cc.Alive) crashes=$($cc.Crashes); $s"
  Cmd-Host 'issue B1 pos'; Start-Sleep 3
  $offer = @($(Host-Json).codes)[-1]; $code = $offer.code
  Log "C1 pos code kind=$($offer.kind) branch=$($offer.branch) code=$code"
  # plain-HTTP decoy
  Pos-Pair-Form $H.plainHttpAddress $code $H.fingerprint
  $txt = Screen-Text; $s = Shot 'c1-plain-http'
  Record 'C1.1 plain-HTTP decoy refused (cashier)' (Pass ((Pos-On-Onboarding) -and ($txt -match 'تعذّر|تعذر|مشفّر|https|Cannot reach|encrypted'))) "stays on pairing; $(Tail $txt 220); $s"
  # wrong fingerprint
  Pos-Pair-Form $H.address $code ('a' * 64)
  $txt = Screen-Text; $s = Shot 'c1-wrong-fp'
  Record 'C1.2 WRONG certificate fingerprint refused (pin enforced, cashier)' (Pass ((Pos-On-Onboarding) -and ($txt -match 'تعذّر|تعذر|Cannot reach'))) "stays on pairing with network/pin error; $(Tail $txt 220); $s"
  # correct pairing with the SAME code
  Pos-Pair-Form $H.address $code $H.fingerprint
  $txt = Screen-Text; $s = Shot 'c1-paired'
  Record 'C1.3 pair over 10.0.2.2 with a branch-bound pos code + typed fingerprint' (Pass (Pos-On-Login)) "sign-in screen shown (same code still valid after the 2 refused attempts); screen: $(Tail $txt 200); $s"
  Cmd-Host 'list'; Start-Sleep 2
  $dev = Get-Content "$($env:LAB_DIR)\devices.json" -Raw | ConvertFrom-Json
  $posRows = @($dev | Where-Object { $_.device_kind -eq 'pos' -and $_.name -eq 'PicPos Cashier' })
  Record 'C1.4 host lists the tablet as kind=pos bound to branch B1' (Pass (($posRows.Count -eq 1) -and ($posRows[0].branch_id -eq $H.branches.B1))) "devices: $(($dev | ConvertTo-Json -Compress -Depth 3)); expected branch id $($H.branches.B1)"
  # a used code cannot pair again
  A shell pm clear $Pkg.pos | Out-Null; Launch $Pkg.pos; Start-Sleep 5
  Pos-Pair-Form $H.address $code $H.fingerprint
  $txt = Screen-Text; $s = Shot 'c1-code-reuse'
  Record 'C1.5 a used pairing code is refused' (Pass ((Pos-On-Onboarding) -and ($txt -match 'الرمز غير صحيح|wrong, already used'))) "$(Tail $txt 200); $s"

  # ---------- C2 sign-in ----------
  $code = Pos-Fresh-Pair
  if (-not $code) { Record 'C2 cashier sign-in' 'BLOCKED' "could not pair the cashier app: $(Screen-Text)"; return }
  Pos-Login 'cashier1' 'definitely-wrong-1'
  $txt = Screen-Text; $s = Shot 'c2-wrong-password'
  Record 'C2.1 wrong password refused' (Pass ((Pos-On-Login) -and ($txt -match 'اسم المستخدم أو كلمة المرور غير صحيحة|بيانات الدخول غير صحيحة|username or password is wrong|sign-in details are wrong'))) "$(Tail $txt 200); $s"
  Pos-Login 'clerk1' 'WhClerk#2026'
  $txt = Screen-Text; $s = Shot 'c2-no-pos-access'
  $hostSays = Pos-Call 'c2-host-noaccess' 'clerk1' 'GET' '/api/branches'
  Record 'C2.2 user WITHOUT pos_access refused (host code pos_access_denied)' (Pass ((Pos-On-Login) -and ($txt -match 'نقطة البيع|point-of-sale') -and ($hostSays.status -eq 403) -and ("$($hostSays.body | ConvertTo-Json -Compress)" -match 'pos_access_denied'))) "app: $(Tail $txt 200); host (pos probe tablet) sign-in clerk1 => $($hostSays.status) $($hostSays.body | ConvertTo-Json -Compress); $s"
  Pos-Login 'cashier1' 'Cashier#2026'
  $txt = Screen-Text; $s = Shot 'c2-cashier-in'; Save-Dump 'c2-cashier-in' | Out-Null
  Record 'C2.3 cashier of the right branch accepted (shell shown)' (Pass (Pos-In-Shell)) "$(Tail $txt 240); $s"

  # ---------- C4 persistence ----------
  A shell am force-stop $Pkg.pos | Out-Null; Start-Sleep 2; Launch $Pkg.pos; Start-Sleep 6
  $txt = Screen-Text; $s = Shot 'c4-restart'
  Record 'C4.1 force-stop + restart keeps pairing and sign-in' (Pass ((-not (Pos-On-Onboarding)) -and (Pos-In-Shell))) "not on pairing screen; in shell=$(Pos-In-Shell); $(Tail $txt 160); $s"
  A shell input keyevent KEYCODE_HOME | Out-Null; Start-Sleep 2; A shell monkey -p $Pkg.pos -c android.intent.category.LAUNCHER 1 | Out-Null; Start-Sleep 3
  Record 'C4.2 background/resume keeps pairing' (Pass (-not (Pos-On-Onboarding))) (Shot 'c4-resume')

  # ---------- C3 revocation (signed in; the app asks the host at its next start) ----------
  Cmd-Host 'revoke-all'; Start-Sleep 3
  $inSession = Screen-Text; $sIn = Shot 'c3-in-session-after-revoke'
  A shell am force-stop $Pkg.pos | Out-Null; Start-Sleep 2; Launch $Pkg.pos; Start-Sleep 8
  $txt = Screen-Text; $s = Shot 'c3-after-restart'; Save-Dump 'c3-after-restart' | Out-Null
  Record 'C3.1 host revokes the tablet -> next start wipes it to the pairing screen and tells the user' (Pass ((Pos-On-Onboarding) -and ($txt -match 'أُلغي ربط هذا الجهاز|office unpaired'))) "in-session screen right after revoke (no call is made while the shell is open): in shell=$(Pos-In-Shell) $sIn ; after restart: $(Tail $txt 240); $s"
  # revoke while the sign-in screen is shown, then sign in (authenticated call)
  $code = Pos-Fresh-Pair
  if ($code) {
    Cmd-Host 'revoke-all'; Start-Sleep 3
    Pos-Login 'cashier1' 'Cashier#2026'
    $txt = Screen-Text; $s = Shot 'c3-login-after-revoke'
    Record 'C3.2 revoked tablet at the sign-in screen: the sign-in call wipes it and tells the user' (Pass ((Pos-On-Onboarding) -and ($txt -match 'أُلغي ربط هذا الجهاز|office unpaired'))) "$(Tail $txt 240); $s"
  } else { Record 'C3.2 revoked tablet at the sign-in screen' 'BLOCKED' 'could not re-pair' }
  # pm clear => unpaired
  $code = Pos-Fresh-Pair
  if ($code) {
    Pos-Login 'cashier1' 'Cashier#2026'
    A shell pm clear $Pkg.pos | Out-Null; Launch $Pkg.pos; for ($w = 0; $w -lt 8 -and -not (Pos-On-Onboarding); $w++) { Start-Sleep 3 }; $s = Shot 'c4-after-pm-clear'
    Record 'C4.3 pm clear -> unpaired' (Pass (Pos-On-Onboarding)) "$s"
  } else { Record 'C4.3 pm clear -> unpaired' 'BLOCKED' 'could not re-pair' }

  # ---------- C5 host-side facts ----------
  $r1 = Pos-Call 'c5-wh-approvals' '-' 'GET' '/api/m1/wh/approvals'
  $r2 = Pos-Call 'c5-wh-info-user' 'cashier1' 'GET' '/api/m1/wh/items?barcode=6221234567890'
  $r3 = Pos-Call 'c5-mirror' '-' 'GET' '/api/mirror/branches'
  $r4 = Pos-Call 'c5-mirror-user' 'cashier1' 'GET' '/api/mirror/sync/state'
  $scope = { param($r) ($r.status -eq 403) -and ("$($r.body | ConvertTo-Json -Compress)" -match 'device_scope') }
  Record 'C5.1 pos device token cannot call /api/m1/wh/* (403 device_scope)' (Pass ((& $scope $r1) -and (& $scope $r2))) "approvals(no user) => $($r1.status) $($r1.body | ConvertTo-Json -Compress); items(cashier1) => $($r2.status) $($r2.body | ConvertTo-Json -Compress)"
  Record 'C5.2 pos device token cannot call /api/mirror/* (403 device_scope)' (Pass ((& $scope $r3) -and (& $scope $r4))) "mirror/branches => $($r3.status) $($r3.body | ConvertTo-Json -Compress); mirror/sync/state(cashier1) => $($r4.status) $($r4.body | ConvertTo-Json -Compress)"
  $s1 = Pos-Call 'c5-sales-branches' 'cashier1' 'GET' '/api/branches'
  $s2 = Pos-Call 'c5-sales-products' 'cashier1' 'GET' '/api/products'
  $s3 = Pos-Call 'c5-sales-list' 'cashier1' 'GET' '/api/sales'
  Record 'C5.3 pos device token + cashier works on ordinary sales routes' (Pass (($s1.status -eq 200) -and ($s2.status -eq 200) -and ($s3.status -eq 200))) "GET /api/branches => $($s1.status); /api/products => $($s2.status); /api/sales => $($s3.status)"

  # legacy shared bearer. The lab host is a NEW server: the DB had no lan_legacy_token_enabled row when startServer ran.
  $lf0 = Legacy-Facts 'c5-legacy-0'
  $lg1 = Legacy-Call 'c5-legacy-fresh' 'GET' '/api/branches'
  $lf1 = Legacy-Facts 'c5-legacy-1'
  $att = @($lf1.attempts | Where-Object { $_.deviceId -eq 'lab-old-phone' })
  Record 'C5.4 freshly provisioned host: shared legacy bearer is OFF (setting absent -> false), refused 401 legacy_token_disabled' (Pass (($H.legacySettingBeforeStart -eq 'null') -and ($lf0.settingLanLegacyTokenEnabled -eq 'false') -and ($lg1.status -eq 401) -and ("$($lg1.body | ConvertTo-Json -Compress)" -match 'legacy_token_disabled'))) "setting before startServer=$($H.legacySettingBeforeStart); after=$($lf0.settingLanLegacyTokenEnabled); old-style bearer => $($lg1.status) $($lg1.body | ConvertTo-Json -Compress)"
  Record 'C5.5 the refused legacy attempt shows in the telemetry' (Pass (($lf1.refusedRequests -ge 1) -and ($att.Count -eq 1) -and ($att[0].refused -ge 1))) "refusedRequests=$($lf1.refusedRequests) accepted=$($lf1.requestsAccepted); attempt lab-old-phone: $($att | ConvertTo-Json -Compress)"
  Host-Do 'setting|lan_legacy_token_enabled|true' | Out-Null
  $lg2 = Legacy-Call 'c5-legacy-enabled' 'GET' '/api/branches'
  $lf2 = Legacy-Facts 'c5-legacy-2'
  Record 'C5.6 host with the legacy bearer ENABLED: an old-style bearer still works' (Pass (($lg2.status -eq 200) -and ($lf2.requestsAccepted -ge 1))) "legacy bearer => $($lg2.status); telemetry accepted=$($lf2.requestsAccepted) refused=$($lf2.refusedRequests)"
  Host-Do 'setting|lan_legacy_token_enabled|false' | Out-Null
  $lg3 = Legacy-Call 'c5-legacy-off-again' 'GET' '/api/branches'
  Record 'C5.7 switching it OFF again refuses the bearer at once' (Pass ($lg3.status -eq 401)) "legacy bearer => $($lg3.status) $($lg3.body | ConvertTo-Json -Compress)"
  $cc = Crash-Check $Pkg.pos
  Record 'C-CRASH cashier app alive / no crash buffer entries during C scenarios' (Pass (-not $cc.Crashes)) "crashes=$($cc.Crashes)"
}
