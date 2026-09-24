$src = 'C:\Users\Эмир\.zcode\workspace\default\radiotrade'
$dst = 'C:\dev\radiotrade'
robocopy $src $dst /E /XD build .dart_tool .vs .idea .git /NFL /NDL /NJH /NJS | Out-Null
Write-Output ('pubspec: ' + (Test-Path "$dst\pubspec.yaml"))
Write-Output ('lib: '     + (Test-Path "$dst\lib\main.dart"))
Write-Output ('android: ' + (Test-Path "$dst\android\gradle.properties"))
Write-Output ('assets: ' + (Test-Path "$dst\assets\telemaster_seed.json"))
