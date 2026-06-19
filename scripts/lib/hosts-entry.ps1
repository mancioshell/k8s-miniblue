<#
.SYNOPSIS
  Add or remove miniblue Key Vault canonical hostnames in the Windows hosts file.

.DESCRIPTION
  azurerm encodes the Key Vault in the data-plane HOST (<name>.vault.azure.net). For the
  terraform host to reach miniblue's canonical KV data plane, that FQDN must resolve to
  127.0.0.1 (miniblue republishes its HTTPS listener on :443). This script manages those
  entries idempotently, tagging each managed line with "# miniblue-kv" so it can be cleaned
  up precisely on teardown. Requires elevation (writes %WINDIR%\System32\drivers\etc\hosts).

.PARAMETER Action
  add    — ensure a "127.0.0.1 <fqdn> # miniblue-kv" line exists for each host.
  remove — delete the miniblue-kv-tagged lines for each host.

.PARAMETER Hosts
  Space-separated list of FQDNs (e.g. "kv-mb-local.vault.azure.net").
#>
param(
  [Parameter(Mandatory = $true)][ValidateSet('add', 'remove')][string]$Action,
  [Parameter(Mandatory = $true)][string]$Hosts
)

$ErrorActionPreference = 'Stop'
$hostsFile = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$tag = '# miniblue-kv'
$fqdns = $Hosts.Split(' ') | Where-Object { $_ -ne '' }

$content = @(Get-Content -Path $hostsFile -ErrorAction SilentlyContinue)

# Drop any existing miniblue-kv-managed line for the target FQDNs (idempotent).
$kept = $content | Where-Object {
  $line = $_
  $drop = $false
  if ($line -match [regex]::Escape($tag)) {
    foreach ($f in $fqdns) {
      if ($line -match ('\s' + [regex]::Escape($f) + '(\s|$)')) { $drop = $true; break }
    }
  }
  -not $drop
}

if ($Action -eq 'add') {
  $additions = foreach ($f in $fqdns) { "127.0.0.1 $f $tag" }
  Set-Content -Path $hostsFile -Value (@($kept) + @($additions)) -Encoding ASCII
  Write-Host ("[+] hosts: ensured " + ($fqdns -join ', ') + " -> 127.0.0.1")
}
else {
  Set-Content -Path $hostsFile -Value $kept -Encoding ASCII
  Write-Host ("[-] hosts: removed " + ($fqdns -join ', '))
}
