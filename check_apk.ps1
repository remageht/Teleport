$apk = 'C:\dev\radiotrade\build\app\outputs\flutter-apk'
if (Test-Path $apk) {
  Get-ChildItem $apk | ForEach-Object {
    '{0}  {1} MB  {2}' -f $_.Name, [math]::Round($_.Length/1MB,1), $_.LastWriteTime
  }
} else {
  Write-Output 'APK folder not found yet'
}
Write-Output '--- java processes ---'
Get-Process java -ErrorAction SilentlyContinue | ForEach-Object {
  'pid {0}  cpu {1}s' -f $_.Id, [int]$_.CPU
}
