<#
.SYNOPSIS
  Register (or remove) the daily Windows scheduled task for backup_postgres.ps1.

.DESCRIPTION
  Creates task "PicPos PostgreSQL Backup" running daily at -At under the CURRENT
  user (interactive logon type: no password is stored; the task runs while the
  user is logged on). The task needs PGPASSWORD (user-level environment variable)
  or %APPDATA%\postgresql\pgpass.conf of that same user. No secret is placed in
  the task definition. Supports -WhatIf. Use -Unregister to remove.

.EXAMPLE
  .\register_postgres_backup_task.ps1 -WhatIf
  .\register_postgres_backup_task.ps1 -At 03:15 -Database picpos
  .\register_postgres_backup_task.ps1 -Unregister
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$At = '02:30',
  [string]$TaskName = 'PicPos PostgreSQL Backup',
  [string]$Database = 'picpos',
  [string]$DbHost = 'localhost',
  [int]$Port = 5432,
  [string]$User = 'postgres',
  [string]$OutDir = '',
  [int]$KeepDaily = 14,
  [int]$KeepWeekly = 8,
  [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

if ($Unregister) {
  if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister-ScheduledTask')) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed task '$TaskName'."
  }
  exit 0
}

$time = [datetime]::MinValue
if (-not [datetime]::TryParseExact($At, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$time)) {
  [Console]::Error.WriteLine("Invalid -At '$At' (expected HH:mm)."); exit 1
}
$script = Join-Path $PSScriptRoot 'backup_postgres.ps1'
if (-not (Test-Path $script)) { [Console]::Error.WriteLine("Missing $script"); exit 1 }

$argList = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Database $Database -DbHost $DbHost -Port $Port -User $User -KeepDaily $KeepDaily -KeepWeekly $KeepWeekly"
if ($OutDir) { $argList += " -OutDir `"$OutDir`"" }

$me = "$env:USERDOMAIN\$env:USERNAME"
if ($PSCmdlet.ShouldProcess($TaskName, "Register-ScheduledTask daily $At as $me : powershell.exe $argList")) {
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argList -WorkingDirectory (Split-Path -Parent $PSScriptRoot)
  $trigger = New-ScheduledTaskTrigger -Daily -At $time
  $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
  Write-Host "Registered '$TaskName' daily at $At as $me."
}
exit 0
