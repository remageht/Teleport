Write-Output '--- NDK folders ---'
Get-ChildItem 'C:\Android\sdk\ndk' -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime | Format-Table
Write-Output '--- downloads in progress ---'
$d = 'C:\Android\sdk\.downloads'
if (Test-Path $d) { Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Select-Object Name, @{n='MB';e={[int]($_.Length/1MB)}}, LastWriteTime | Format-Table } else { Write-Output 'no .downloads folder' }
Write-Output '--- java/gradle processes ---'
Get-Process java, 'java.exe' -ErrorAction SilentlyContinue | Select-Object Id, @{n='CPU_s';e={[int]$_.CPU}}, @{n='RAM_MB';e={[int]($_.WorkingSet64/1MB)}} | Format-Table
