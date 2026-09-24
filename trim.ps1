$f = Join-Path (Get-Location) 'lib\features\warehouse\warehouse_screen.dart'
$lines = Get-Content $f
$idx = ($lines | Select-String -Pattern 'class _ProductTile').LineNumber
Write-Output "tile starts at line $idx of $($lines.Count)"
$kept = $lines[0..($idx[0] - 2)]
Set-Content $f -Value $kept -Encoding UTF8
Write-Output "kept $($kept.Count) lines"
