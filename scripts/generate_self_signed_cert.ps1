<#
.SYNOPSIS
    يولّد شهادةً ذاتيّةَ التوقيع لتشغيل الخادم المحلّيّ عبر HTTPS.

.DESCRIPTION
    ⚠️ هذا السكربت كانت شاشةُ الإعدادات تحيل إليه **وهو غيرُ موجود** — أي
    أنّ المشغّلَ يُطلَب منه توليدُ شهادةٍ بأداةٍ لا وجودَ لها. هذا الملفّ
    يسدُّ تلك الفجوة.

    يُخرج ملفَّين بصيغة PEM في مجلَّدٍ من اختيارك:
      • cert.pem  — الشهادة (تُعطى لحقل «ملف الشهادة»)
      • key.pem   — المفتاح الخاصّ (يُعطى لحقل «ملف المفتاح»)

    والشهادةُ تحمل SAN لكلِّ عنوانٍ يُخاطَب به الخادم — العنوانُ المحلّيّ
    و`localhost` و`127.0.0.1` — لأنّ شهادةً بلا SAN مطابقٍ تُرفض من كثيرٍ
    من المكدّسات حتّى مع تعطيل التحقّق من الاسم.

    ولا يهمّ أنّ الشهادةَ ذاتيّةُ التوقيع: الأجهزةُ لا تتحقّق من سلسلة
    الثقة بل من **بصمة الشهادة** التي تُثبَّت في نافذة الاقتران. فالبصمةُ
    هي الهويّة، ولا حاجةَ إلى جهةِ إصدار.

.PARAMETER OutDir
    مجلَّدُ الإخراج. الافتراضيّ: مجلَّدٌ فرعيٌّ `certs` بجوار السكربت.

.PARAMETER IpAddress
    عنوانُ الخادم على الشبكة. يُكتشَف تلقائياً إن أُهمل.

.PARAMETER Days
    مدّةُ الصلاحية بالأيّام. الافتراضيّ 3650 (عشرُ سنوات).

    ⚠️ طويلةٌ عن قصد: انتهاءُ الشهادة يقطع كلَّ الأجهزة دفعةً واحدة، ولا
    آليّةَ تجديدٍ تلقائيّ هنا. والبصمةُ المثبَّتةُ هي ضابطُ الأمان لا المدّة.

.EXAMPLE
    .\generate_self_signed_cert.ps1
    .\generate_self_signed_cert.ps1 -IpAddress 192.168.1.50 -OutDir C:\picpos-certs
#>

[CmdletBinding()]
param(
    [string] $OutDir,
    [string] $IpAddress,
    [int]    $Days = 3650
)

$ErrorActionPreference = 'Stop'

if (-not $OutDir) {
    $OutDir = Join-Path $PSScriptRoot 'certs'
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# ── اكتشافُ عنوان الشبكة ───────────────────────────────────────────────
if (-not $IpAddress) {
    $candidate = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -ne '127.0.0.1' -and
            $_.PrefixOrigin -in @('Dhcp', 'Manual') -and
            $_.IPAddress -notlike '169.254.*'
        } |
        Sort-Object -Property InterfaceMetric |
        Select-Object -First 1
    if ($candidate) { $IpAddress = $candidate.IPAddress }
}
if (-not $IpAddress) {
    throw "تعذّر اكتشافُ عنوان الشبكة. مرّره صراحةً: -IpAddress 192.168.1.50"
}

$certPath = Join-Path $OutDir 'cert.pem'
$keyPath  = Join-Path $OutDir 'key.pem'

Write-Host ""
Write-Host "  العنوان : $IpAddress"
Write-Host "  المجلَّد : $OutDir"
Write-Host "  الصلاحية: $Days يوماً"
Write-Host ""

# ── المسارُ المفضَّل: openssl ────────────────────────────────────────────
# يُخرج PEM مباشرةً بلا وسائط، وهو ما يقبله `SecurityContext` في Dart.
$openssl = Get-Command openssl -ErrorAction SilentlyContinue

if ($openssl) {
    Write-Host "[1/2] توليدٌ بـopenssl…"
    $cnf = Join-Path $env:TEMP "picpos_cert_$([guid]::NewGuid().ToString('N')).cnf"
    @"
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[dn]
CN = $IpAddress
O  = PicPos Local Server

[v3]
subjectAltName   = IP:$IpAddress, IP:127.0.0.1, DNS:localhost
basicConstraints = critical, CA:FALSE
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
"@ | Set-Content -Path $cnf -Encoding ascii

    try {
        & openssl req -x509 -newkey rsa:2048 -nodes `
            -keyout $keyPath -out $certPath `
            -days $Days -config $cnf 2>&1 | Out-String | Write-Verbose
        if ($LASTEXITCODE -ne 0) { throw "openssl خرج بالرمز $LASTEXITCODE" }
    }
    finally {
        Remove-Item $cnf -Force -ErrorAction SilentlyContinue
    }
}
else {
    # ── مسارٌ بديل: .NET (‏يحتاج PowerShell 7 / .NET 5+) ────────────────
    Write-Host "[1/2] openssl غيرُ موجود — توليدٌ بـ.NET…"

    $cert = New-SelfSignedCertificate `
        -Subject "CN=$IpAddress, O=PicPos Local Server" `
        -TextExtension @("2.5.29.17={text}IPAddress=$IpAddress&IPAddress=127.0.0.1&DNS=localhost") `
        -KeyAlgorithm RSA -KeyLength 2048 `
        -NotAfter (Get-Date).AddDays($Days) `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy Exportable

    try {
        if (-not ($cert.PSObject.Methods.Name -contains 'ExportCertificatePem')) {
            throw @"
إصدارُ PowerShell هنا لا يدعم تصديرَ PEM مباشرةً.
ثبّت openssl ثمّ أعد التشغيل — أسهلُ طريق:
    winget install ShiningLight.OpenSSL.Light
"@
        }
        $cert.ExportCertificatePem() | Set-Content -Path $certPath -Encoding ascii
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        $rsa.ExportPkcs8PrivateKeyPem() | Set-Content -Path $keyPath -Encoding ascii
    }
    finally {
        Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $certPath) -or -not (Test-Path $keyPath)) {
    throw "لم تُكتَب الملفّات. راجع المخرَجات أعلاه."
}

# ── البصمة ─────────────────────────────────────────────────────────────
# نفسُ البصمة التي ينشرها الخادمُ في `/api/health` داخلَ نافذة الاقتران،
# ويثبّتها العميل. تُطبَع هنا ليقارنها المشغّلُ بعينه إن أراد.
Write-Host "[2/2] حسابُ البصمة…"
$pem   = (Get-Content $certPath -Raw)
$b64   = ($pem -replace '-----BEGIN CERTIFICATE-----', '' `
                -replace '-----END CERTIFICATE-----', '') -replace '[^A-Za-z0-9+/=]', ''
$der   = [Convert]::FromBase64String($b64)
$sha   = [System.Security.Cryptography.SHA256]::Create()
$fp    = ($sha.ComputeHash($der) | ForEach-Object { $_.ToString('x2') }) -join ''

Write-Host ""
Write-Host "  ✅ تمّ."
Write-Host ""
Write-Host "  الشهادة : $certPath"
Write-Host "  المفتاح : $keyPath"
Write-Host "  البصمة  : $fp"
Write-Host ""
Write-Host "  الخطوات التالية:"
Write-Host "    ١. الإعدادات ← وضع الشبكة ← فعّل TLS واختر الملفَّين أعلاه."
Write-Host "    ٢. أعد تشغيل الخادم (المفتاح معطَّلٌ والخادمُ يعمل)."
Write-Host "    ٣. افتح «نافذة اقتران جهاز جديد» ثمّ اربط كلَّ جهاز."
Write-Host ""
Write-Host "  ⚠️ احتفظ بـkey.pem سرّاً — من يملكه ينتحل شخصيّةَ الخادم."
Write-Host ""
