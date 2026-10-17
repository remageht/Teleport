# Генератор синтетической накладной (PNG) для бенча OCR.
# Только ASCII: кириллица приходит из JSON (UTF-8), чтобы не зависеть
# от кодировки консоли PowerShell 5.1.
# Запуск:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool/gen_synthetic_invoice.ps1 `
#     -Json tool/ocr_bench_invoice.json -Out build/ocr_bench/invoice_clean.png
param(
  [Parameter(Mandatory = $true)][string]$Json,
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$data = [System.IO.File]::ReadAllText(
    [System.IO.Path]::GetFullPath($Json),
    [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$inv = $data.meta
$lab = $data.labels

function Fmt2([double]$v, [bool]$group = $false) {
  $s = $v.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
  if ($group) {
    $parts = $s.Split('.')
    $intp = $parts[0]
    $rev = ''
    $cnt = 0
    for ($k = $intp.Length - 1; $k -ge 0; $k--) {
      if ($cnt -gt 0 -and $cnt % 3 -eq 0) { $rev += ' ' }
      $rev += $intp[$k]
      $cnt++
    }
    $chars = $rev.ToCharArray()
    [array]::Reverse($chars)
    $s = (-join $chars) + '.' + $parts[1]
  }
  return $s.Replace('.', ',')
}

$W = 1654
$H = 2339
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::White)

$black = [System.Drawing.Brushes]::Black
$font = New-Object System.Drawing.Font('Arial', 28)
$fontB = New-Object System.Drawing.Font('Arial', 28, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font('Arial', 36, [System.Drawing.FontStyle]::Bold)
$fontSmall = New-Object System.Drawing.Font('Arial', 24)
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 2.0)

# Подбирает наибольший из типовых кеглей, влезающий в ширину ячейки:
# в реальных накладных длинные артикулы/суммы печатаются мельче.
function FitFont([string]$text, $bold, [float]$maxW) {
  foreach ($sz in @(28, 26, 24, 22, 20, 18, 16)) {
    $style = [System.Drawing.FontStyle]::Regular
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
    $f = New-Object System.Drawing.Font('Arial', $sz, $style)
    if ($g.MeasureString($text, $f).Width -le $maxW) { return $f }
  }
  return $f
}

function Txt([string]$text, $f, [float]$x, [float]$y, [float]$w = 1450) {
  $rect = New-Object System.Drawing.RectangleF($x, $y, $w, 70)
  $g.DrawString($text, $f, $black, $rect)
}

Txt ("$($lab.supplier) $($inv.supplier)") $fontSmall 100 90
Txt ("$($lab.buyer) $($inv.buyer)") $fontSmall 100 130
Txt $inv.address $fontSmall 100 170
Txt $lab.title $fontTitle 100 240
Txt $lab.order $font 100 310

# Таблица: x-границы колонок и строки
$cols = @(100, 160, 340, 570, 1100, 1270, 1390, 1554)
$top = 390
$rowH = 88
$rows = $data.products.Count

for ($c = 0; $c -lt 8; $c++) {
  $g.DrawLine($pen, $cols[$c], $top, $cols[$c], $top + $rowH * ($rows + 1))
}
for ($r = 0; $r -le ($rows + 1); $r++) {
  $g.DrawLine($pen, 100, $top + $r * $rowH, 1554, $top + $r * $rowH)
}

# Шапка таблицы (по центру ячеек)
for ($c = 0; $c -lt 7; $c++) {
  $rect = New-Object System.Drawing.RectangleF(
      ($cols[$c] + 4), ($top + 6), ($cols[$c + 1] - $cols[$c] - 8), ($rowH - 12))
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $hf = FitFont $lab.header[$c] $true ($cols[$c + 1] - $cols[$c] - 16)
  $g.DrawString($lab.header[$c], $hf, $black, $rect, $sf)
}

# Строки товаров
$sumTotal = 0.0
for ($i = 0; $i -lt $rows; $i++) {
  $p = $data.products[$i]
  $y = $top + ($i + 1) * $rowH
  $sum = [double]$p.qty * [double]$p.price
  $sumTotal += $sum

  $cells = @(
    ([string]($i + 1)),
    ([string]$p.article),
    ([string]$p.barcode),
    ([string]$p.name),
    ([string]$p.qty),
    (Fmt2 $p.price),
    (Fmt2 $sum $true)
  )
  for ($c = 0; $c -lt 7; $c++) {
    $isLeft = ($c -eq 1 -or $c -eq 3)
    $rect = New-Object System.Drawing.RectangleF(
        ($cols[$c] + 5), ($y + 4), ($cols[$c + 1] - $cols[$c] - 10), ($rowH - 8))
    $sf = New-Object System.Drawing.StringFormat
    if ($isLeft) {
      $sf.Alignment = [System.Drawing.StringAlignment]::Near
    } else {
      $sf.Alignment = [System.Drawing.StringAlignment]::Center
    }
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $cf = FitFont $cells[$c] $false ($cols[$c + 1] - $cols[$c] - 14)
    $g.DrawString($cells[$c], $cf, $black, $rect, $sf)
  }
}

# Подвал: итог, наименования, адрес/телефон (мусор для фильтра парсера)
$yf = $top + ($rows + 1) * $rowH + 30
$rectI = New-Object System.Drawing.RectangleF(1150, $yf, 404, 50)
$sfI = New-Object System.Drawing.StringFormat
$sfI.Alignment = [System.Drawing.StringAlignment]::Far
$g.DrawString("$($lab.itogo) $(Fmt2 ([double]$inv.total) $true)", $fontB, $black, $rectI, $sfI)
Txt $lab.vsego $font 100 ($yf + 60)

$g.Dispose()
$bmp.Save(
    [System.IO.Path]::GetFullPath($Out),
    [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "OK $Out total=$sumTotal"
