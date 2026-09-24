# Сборка дистрибутива ТелеПорт: dist/ с exe-папкой и apk
# Версия дистрибутива — в одном месте.
param([string]$Root = 'C:\dev\radiotrade')
$Ver = '1.2.7'

Stop-Process -Name TelePort -Force -ErrorAction SilentlyContinue

$dist = Join-Path $Root 'dist'
# Архивация предыдущего dist, чтобы старые версии не терялись.
if (Test-Path $dist) {
  $archRoot = Join-Path $Root 'dist-archive'
  New-Item -ItemType Directory -Path $archRoot -Force | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  Copy-Item $dist (Join-Path $archRoot "dist_$stamp") -Recurse -Force
  # Храним 5 последних архивов.
  Get-ChildItem $archRoot -Directory | Sort-Object Name -Descending |
    Select-Object -Skip 5 | Remove-Item -Recurse -Force
}
# Снос с ретраями: свежезакрытый exe/антивирус могут держать файлы пару секунд.
for ($i = 0; $i -lt 3 -and (Test-Path $dist); $i++) {
  Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $dist) { Start-Sleep 3 }
}
New-Item -ItemType Directory -Path $dist | Out-Null

# 1. Windows: копия Release с переименованным exe
$win = Join-Path $dist "TelePort_${Ver}_Windows_x64"
Copy-Item (Join-Path $Root 'build\windows\x64\runner\Release') $win -Recurse
Rename-Item (Join-Path $win 'radiotrade.exe') 'TelePort.exe'
# Данные БД живут в %APPDATA%, так что переименование безопасно.

# 2. Архив для распространения
Compress-Archive -Path $win -DestinationPath (Join-Path $dist "TelePort_${Ver}_Windows_x64.zip")

# 3. Android APK по архитектурам (сплиты: arm64 — современные телефоны,
# armeabi-v7a — старые 32-бит, x86_64 — эмуляторы). Сплит весит ~втрое
# меньше жирного APK, т.к. содержит нативный код только одной архитектуры.
$apkDir = Join-Path $Root 'build\app\outputs\flutter-apk'
foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
  $src = Join-Path $apkDir "app-$abi-release.apk"
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $dist "TelePort_${Ver}_Android_$abi.apk")
  }
}
# Жирный APK не кладём: сплиты выше покрывают все архитектуры,
# а лежалый fat только вводит в заблуждение версией.

# 4. Инструкция
@"
================================================================
  ТелеПорт $Ver — мобильная торговля ТЕЛЕМАСТЕР
  (склад, каталоги, продажи, дашборд дня, популярность, синхронизация, Excel-экспорт)
================================================================

WINDOWS (.exe)
  1) Распакуйте папку TelePort_${Ver}_Windows_x64 целиком.
  2) Запустите TelePort.exe.
  Требования: Windows 10/11 x64. Интернет нужен только для
  синхронизации; база хранится локально на компьютере.

ANDROID (.apk) — берите файл под свой процессор:
  TelePort_${Ver}_Android_arm64-v8a.apk — почти все современные телефоны;
  TelePort_${Ver}_Android_armeabi-v7a.apk — старые 32-битные;
  TelePort_${Ver}_Android_x86_64.apk — эмуляторы.
  1) Скопируйте нужный apk на телефон/планшет.
  2) Откройте файл -> разрешите «Установка из неизвестных
     источников» -> Установить.

СИНХРОНИЗАЦИЯ ПК <-> ТЕЛЕФОН
  1) Оба устройства в одной Wi-Fi сети.
  2) На ПК: Настройки -> «Сервер синхронизации» -> ВКЛ
     (при первом включении разрешите доступ в брандмауэре Windows).
  3) На телефоне: Настройки -> введите адрес ПК (показан на ПК,
     вида 192.168.0.102:8180) -> «Обменять данные».
  Передаются: товары, остатки, цены, популярность, заказы.

ЭКСПОРТ ПРОДАЖ В EXCEL
  Отчёты -> «Экспорт в Excel» (за сегодня или всё время).
  На ПК файл в папке «Документы», на телефоне — меню «Поделиться».

ПЕРВАЯ НАСТРОЙКА
  Вход не требуется. Демо-данные отсутствуют: база наполняется
  вашими накладными при первом запуске (если поставляется вместе
  с базой) или добавляется вручную (+ на складе).
"@ | Set-Content (Join-Path $dist 'ИНСТРУКЦИЯ.txt') -Encoding UTF8

Get-ChildItem $dist | ForEach-Object { '{0}  {1:N1} MB' -f $_.Name, ($_.Length / 1MB) }
Write-Output '--- win folder ---'
Get-ChildItem $win | ForEach-Object { $_.Name }
