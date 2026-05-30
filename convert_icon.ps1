Add-Type -AssemblyName System.Drawing
$pngPath = 'E:\Desktop\code\Projects\Clicker\icon.png'
$icoPath = 'E:\Desktop\code\Projects\Clicker\windows\runner\resources\app_icon.ico'
$png = [System.Drawing.Image]::FromFile($pngPath)
Write-Host "PNG size: $($png.Width)x$($png.Height)"

$sizes = @(16, 32, 48, 256)
$bitmaps = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($png, 0, 0, $s, $s)
    $g.Dispose()
    $bitmaps += $bmp
}
$png.Dispose()

$iconCount = $bitmaps.Count
$entrySize = 16
$headerSize = 6
$dataStart = $headerSize + ($iconCount * $entrySize)

$imageDataList = @()
foreach ($bmp in $bitmaps) {
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $ms = New-Object System.IO.MemoryStream
    $icon.Save($ms)
    $ms.Position = 0
    $br = New-Object System.IO.BinaryReader($ms)
    $br.BaseStream.Position = 6 + 16
    $imgData = $br.ReadBytes($ms.Length - 22)
    $br.Dispose()
    $ms.Dispose()
    $imageDataList += ,$imgData
}

$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)

$bw.Write([UInt16]0)
$bw.Write([UInt16]$iconCount)

$offset = $dataStart
for ($i = 0; $i -lt $iconCount; $i++) {
    $bmp = $bitmaps[$i]
    $w = if ($bmp.Width -ge 256) { [byte]0 } else { [byte]$bmp.Width }
    $h = if ($bmp.Height -ge 256) { [byte]0 } else { [byte]$bmp.Height }
    $bw.Write($w)
    $bw.Write($h)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$imageDataList[$i].Length)
    $bw.Write([UInt32]$offset)
    $offset += $imageDataList[$i].Length
}

foreach ($imgData in $imageDataList) {
    $bw.Write($imgData)
}

$bw.Dispose()
$fs.Dispose()

foreach ($bmp in $bitmaps) { $bmp.Dispose() }

Write-Host "ICO created at: $icoPath, size: $((Get-Item $icoPath).Length) bytes"
