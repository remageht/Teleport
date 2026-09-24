# Ставим APK (arm64 — для современного телефона), запускаем exe из dist,
# показываем IP компьютера. Для 32-битных аппаратов — вручную
# TelePort_*_armeabi-v7a.apk из dist.
& 'C:\Android\sdk\platform-tools\adb.exe' install -r 'C:\dev\radiotrade\dist\TelePort_1.2.6_Android_arm64-v8a.apk' | Select-Object -Last 1
Start-Process 'C:\dev\radiotrade\dist\TelePort_1.2.6_Windows_x64\TelePort.exe'
Start-Sleep 4
$pid2 = (Get-Process TelePort -ErrorAction SilentlyContinue).Id
Write-Output "exe pid: $pid2"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { "PC IP: $($_.IPAddress)" }
