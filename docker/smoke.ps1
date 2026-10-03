# End-to-end smoke test against the running TEST stack (Windows PowerShell 5.1 or 7).
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File .\smoke.ps1 [-Base http://localhost:18080]
param([string]$Base = 'http://localhost:18080', [string]$AdminKey = 'test-admin-key')
$ErrorActionPreference = 'Stop'

$health = Invoke-RestMethod "$Base/health"
"health: $($health.status) db=$($health.db) whatsapp=$($health.whatsappProvider)"

# Demo ids come from server/lib/src/seed.dart (SEED_DEMO=true)
$company = '00000000-0000-4000-8000-000000000001'
$rep1 = '00000000-0000-4000-8000-0000000000a1'
$code = (Invoke-RestMethod -Method Post "$Base/admin/pairing-codes" -Headers @{ 'x-admin-key' = $AdminKey } `
    -ContentType 'application/json' -Body (@{ companyGlobalId = $company; employeeGlobalId = $rep1 } | ConvertTo-Json)).code
"pairing code: $code"

$deviceId = [guid]::NewGuid().ToString()
$pair = Invoke-RestMethod -Method Post "$Base/mobile/pair" -ContentType 'application/json' `
    -Body (@{ code = $code; deviceId = $deviceId; deviceName = 'smoke' } | ConvertTo-Json)
$h = @{ Authorization = "Bearer $($pair.deviceToken)"; 'x-device-id' = $deviceId }
$login = Invoke-RestMethod -Method Post "$Base/mobile/login" -Headers $h -ContentType 'application/json' -Body '{"pin":"1234"}'
$h['x-session-token'] = $login.sessionToken

$boot = Invoke-RestMethod "$Base/mobile/bootstrap" -Headers $h
"bootstrap: customers=$($boot.customers.Count) products=$($boot.products.Count) vanStock=$($boot.vanStock.Count) books=$($boot.voucherBooks.Count)"
$lease = $boot.leases | Where-Object docType -eq 'sales_invoice'
$number = "$($lease.prefix)$($lease.nextNumber)"

$doc = @{
  kind = 'sales_invoice'; globalId = [guid]::NewGuid().ToString(); number = $number
  date = (Get-Date).ToUniversalTime().ToString('o'); customerGlobalId = '00000000-0000-4000-8000-0000000000c1'
  lines = @(@{ productGlobalId = '00000000-0000-4000-8000-0000000000b1'; quantity = 2; unitPrice = 2.5 })
  paid = 5.8
}
$push = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = @($doc) } | ConvertTo-Json -Depth 6)
"push: $($push.results[0].status) $($push.results[0].number) total=$($push.results[0].total)"
$again = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = @($doc) } | ConvertTo-Json -Depth 6)
"replay: $($again.results[0].status)"

# I-2: sales return against the invoice line (1 of 2 water), replayed once
$rlease = $boot.leases | Where-Object docType -eq 'sales_return'
$ret = @{
  kind = 'sales_return'; globalId = [guid]::NewGuid().ToString(); number = "$($rlease.prefix)$($rlease.nextNumber)"
  date = (Get-Date).ToUniversalTime().ToString('o'); originalInvoiceGlobalId = $doc.globalId
  lines = @(@{ productGlobalId = '00000000-0000-4000-8000-0000000000b1'; quantity = 1 }); reason = 'damaged'
}
$rp = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = @($ret) } | ConvertTo-Json -Depth 6)
"return: $($rp.results[0].status) $($rp.results[0].number) total=$($rp.results[0].total) cashRefund=$($rp.results[0].cashRefund)"
if ($rp.results[0].status -ne 'accepted') { throw "return not accepted: $($rp.results[0] | ConvertTo-Json -Compress)" }
$ret.globalId = [guid]::NewGuid().ToString(); $ret.number = "$($rlease.prefix)$($rlease.nextNumber + 1)"
$ret.lines = @(@{ productGlobalId = '00000000-0000-4000-8000-0000000000b1'; quantity = 5 })
$over = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = @($ret) } | ConvertTo-Json -Depth 6)
"return over sold: $($over.results[0].status) $($over.results[0].code)"
if ($over.results[0].code -ne 'return_qty_exceeds_sold') { throw 'over-return not rejected' }

# I-2: visits (visited + no-sale with reason)
$visits = @(
  @{ kind = 'visit'; globalId = [guid]::NewGuid().ToString(); customerGlobalId = '00000000-0000-4000-8000-0000000000c1'
     date = (Get-Date).ToUniversalTime().ToString('o'); outcome = 'visited' },
  @{ kind = 'visit'; globalId = [guid]::NewGuid().ToString(); customerGlobalId = '00000000-0000-4000-8000-0000000000c2'
     date = (Get-Date).ToUniversalTime().ToString('o'); outcome = 'no_sale'; noSaleReason = 'closed' }
)
$vp = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = $visits } | ConvertTo-Json -Depth 6)
"visits: $(($vp.results | ForEach-Object status) -join ',')"
if (($vp.results | Where-Object status -ne 'accepted').Count) { throw 'visit rejected' }

# K-1: rep expense from the custody (payment-book leaf, receipt photo, GPS), replayed once,
# then the same leaf again under another globalId (book rule)
$pbook = $boot.paymentBooks | Select-Object -First 1
if (-not $pbook) { throw 'no payment book in bootstrap' }
"expense setup: categories=$($boot.expenseCategories.Count) book=$($pbook.prefix)$($pbook.nextNumber) custody=$($boot.custodyBalance) policy=$($boot.expenseOverCustody)"
$jpeg = [Convert]::ToBase64String([byte[]](0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9))
$exp = @{
  kind = 'expense'; globalId = [guid]::NewGuid().ToString(); date = (Get-Date).ToUniversalTime().ToString('o')
  categoryGlobalId = $boot.expenseCategories[0].globalId; amount = 3.5; note = 'smoke fuel'
  bookGlobalId = $pbook.globalId; bookNumber = [int]$pbook.nextNumber
  photo = @{ mime = 'image/jpeg'; data = $jpeg }
  geo = @{ lat = 31.95; lng = 35.91; accuracy = 8; at = (Get-Date).ToUniversalTime().ToString('o') }
}
$ep = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = @($exp, $exp) } | ConvertTo-Json -Depth 6)
"expense: $($ep.results[0].status) $($ep.results[0].number) overCustody=$($ep.results[0].overCustody) custody=$($ep.results[0].custodyBalance); replay: $($ep.results[1].status)"
if ($ep.results[0].status -ne 'accepted' -or $ep.results[1].status -ne 'duplicate') { throw "expense not accepted once: $($ep.results | ConvertTo-Json -Compress)" }
$exp2 = $exp.Clone(); $exp2.globalId = [guid]::NewGuid().ToString(); $exp2.Remove('photo')
$eu = Invoke-RestMethod -Method Post "$Base/mobile/sync/push" -Headers $h -ContentType 'application/json' `
    -Body (@{ documents = @($exp2) } | ConvertTo-Json -Depth 6)
"expense same leaf: $($eu.results[0].status) $($eu.results[0].code)"
if ($eu.results[0].code -ne 'book_leaf_used') { throw 'used payment leaf not rejected' }

# I-2: device token rotation (new token authenticates)
$rot = Invoke-RestMethod -Method Post "$Base/mobile/token/rotate" -Headers $h
$h['Authorization'] = "Bearer $($rot.deviceToken)"

$pull = Invoke-RestMethod "$Base/mobile/sync/pull?since=$($boot.serverTime)" -Headers $h
"pull: customers=$($pull.customers.Count) vanStock=$($pull.vanStock.Count) documents=$($pull.documents.Count) invoices=$($pull.invoices.Count) (token rotated)"

# I-3: desktop link — credential, pending field documents, ack (posted)
$link = Invoke-RestMethod -Method Post "$Base/admin/desktop-links" -Headers @{ 'x-admin-key' = $AdminKey } `
    -ContentType 'application/json' -Body (@{ companyGlobalId = $company; name = 'smoke desktop' } | ConvertTo-Json)
$dh = @{ Authorization = "Bearer $($link.linkSecret)"; 'x-desktop-link' = $link.linkId }
$ping = Invoke-RestMethod "$Base/desktop/ping" -Headers $dh
"desktop ping: company=$($ping.company.globalId) pending invoices=$($ping.pending.sales_invoice)"
$ack = Invoke-RestMethod -Method Post "$Base/desktop/documents/ack" -Headers $dh -ContentType 'application/json' `
    -Body (@{ results = @(@{ kind = 'sales_invoice'; globalId = $doc.globalId; status = 'posted'; desktopId = '1'; desktopNumber = 'SMOKE-1' }) } | ConvertTo-Json -Depth 5)
"desktop ack: $($ack.results[0].status)"
if ($ack.results[0].status -ne 'posted') { throw 'desktop ack failed' }
$ping2 = Invoke-RestMethod "$Base/desktop/ping" -Headers $dh
if ($ping2.pending.sales_invoice -ne $ping.pending.sales_invoice - 1) { throw 'posted invoice still pending' }
"desktop pending after ack: invoices=$($ping2.pending.sales_invoice)"

# K-1: the expense reaches the desktop feed with its GPS and photo, then is acknowledged
$pend = Invoke-RestMethod "$Base/desktop/documents/pending?limit=500" -Headers $dh
$pexp = $pend.documents | Where-Object { $_.kind -eq 'expense' -and $_.globalId -eq $exp.globalId }
if (-not $pexp) { throw 'expense not in the desktop feed' }
"desktop expense: $($pexp.number) amount=$($pexp.amount) category=$($pexp.categoryName) geo=$($pexp.geo.status) photo=$($pexp.hasPhoto)"
if ($pexp.geo.status -ne 'ok' -or -not $pexp.hasPhoto) { throw 'expense geo/photo missing' }
$att = Invoke-RestMethod "$Base/desktop/documents/attachment?globalId=$($exp.globalId)" -Headers $dh
if ($att.data -ne $jpeg) { throw 'expense photo differs' }
$eack = Invoke-RestMethod -Method Post "$Base/desktop/documents/ack" -Headers $dh -ContentType 'application/json' `
    -Body (@{ results = @(@{ kind = 'expense'; globalId = $exp.globalId; status = 'posted'; desktopId = '2'; desktopNumber = 'SMOKE-PV' }) } | ConvertTo-Json -Depth 5)
"desktop expense ack: $($eack.results[0].status)"
if ($eack.results[0].status -ne 'posted') { throw 'expense ack failed' }

$null = Invoke-RestMethod -Method Post "$Base/admin/whatsapp/process" -Headers @{ 'x-admin-key' = $AdminKey }
$out = Invoke-RestMethod "$Base/admin/whatsapp/outbox" -Headers @{ 'x-admin-key' = $AdminKey }
"whatsapp outbox: $($out.messages[0].template) -> $($out.messages[0].to_phone) status=$($out.messages[0].status)"
