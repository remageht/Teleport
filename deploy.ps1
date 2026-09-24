# Ставим APK, запускаем exe из dist, показываем IP компьютера
& 'C:\Android\sdk\platform-tools\adb.exe' install -r 'C:\dev\radiotrade\dist\TelePort_1.0.0_Android.apk' | Select-Object -Last 1
Start-Process 'C:\dev\radiotrade\dist\TelePort_1.0.0_Windows_x64\TelePort.exe'
Start-Sleep 4
$pid2 = (Get-Process TelePort -ErrorAction SilentlyContinue).Id
Write-Output "exe pid: $pid2"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { "PC IP: $($_.IPAddress)" }
