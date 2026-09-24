Get-ChildItem 'lib' -Recurse -Filter *.dart | ForEach-Object {
  $t = Get-Content $_.FullName -Raw -Encoding UTF8
  if ($t -match 'Р[°-ѕР]') { Write-Output "BROKEN: $($_.Name)" }
}
Write-Output 'scan done'
