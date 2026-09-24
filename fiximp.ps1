$f = Join-Path (Get-Location) 'lib\features\warehouse\warehouse_screen.dart'
$lines = Get-Content $f -Encoding UTF8
$kept = $lines | Where-Object { $_ -notmatch "shared/anim.dart" }
Set-Content $f -Value $kept -Encoding UTF8
Write-Output "removed anim import; lines: $($kept.Count)"
