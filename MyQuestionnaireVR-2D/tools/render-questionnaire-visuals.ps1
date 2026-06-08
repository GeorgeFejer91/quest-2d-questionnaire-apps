param(
    [string]$UnityAndroidRoot = "C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer",
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ConfigPath = "",
    [string]$ReferenceProjectPath = "C:\Users\cogpsy-vrlab\Documents\GithubVR\MyQuestionnaireVR",
    [string]$OutputRoot = "",
    [string]$RunId = "",
    [string]$Sizes = "1280x800,900x800",
    [string]$Serial = "",
    [string]$Adb = "",
    [switch]$CheckQuestForeground,
    [switch]$RequireQuestForeground,
    [switch]$LaunchBeforeForegroundCheck,
    [switch]$SkipAssetRefresh
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$package = "org.questquestionnaire.questionnaires2d"
$activity = "org.questquestionnaire.questionnaires2d.MainActivity"
$deviceExports = "/sdcard/Android/data/$package/files/QuestionnaireExports"

function Resolve-Adb {
    param([string]$RequestedAdb)

    if (-not [string]::IsNullOrWhiteSpace($RequestedAdb)) {
        if (Test-Path -LiteralPath $RequestedAdb) { return $RequestedAdb }
        throw "ADB not found: $RequestedAdb"
    }

    $mqdhAdb = "C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe"
    $unityAdb = Join-Path $UnityAndroidRoot 'SDK\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $mqdhAdb) { return $mqdhAdb }
    if (Test-Path -LiteralPath $unityAdb) { return $unityAdb }
    throw "ADB not found. Pass -Adb explicitly."
}

function Resolve-Serial {
    param(
        [string]$AdbPath,
        [string]$RequestedSerial,
        [string]$EvidenceDir
    )

    $devicesPath = Join-Path $EvidenceDir 'adb-devices.txt'
    $devices = & $AdbPath devices -l 2>&1
    $devices | Set-Content -LiteralPath $devicesPath -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($RequestedSerial)) {
        return $RequestedSerial
    }

    $online = @($devices | Where-Object { $_ -match '^\S+\s+device\s' })
    if ($online.Count -eq 1) {
        return (($online[0] -split '\s+')[0])
    }

    if ($online.Count -gt 1) {
        throw "Multiple online Android devices detected. Pass -Serial explicitly."
    }

    throw "No online Android device detected. See $devicesPath"
}

function Invoke-GradleRender {
    param(
        [string]$GradlePath,
        [string[]]$Arguments
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        & $GradlePath @Arguments
        if ($LASTEXITCODE -eq 0) {
            return
        }

        if ($attempt -eq 1) {
            Write-Warning "Gradle render command failed once; retrying to avoid transient daemon-stop failures."
        }
    }

    throw "Android render validation task failed."
}

function Invoke-AdbText {
    param(
        [string]$AdbPath,
        [string]$DeviceSerial,
        [string[]]$Arguments,
        [string]$OutputPath
    )

    $output = & $AdbPath -s $DeviceSerial @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return $exitCode
}

function Get-ExportRecords {
    param([string]$ExportDir)

    $records = @()
    $jsonFiles = Get-ChildItem -LiteralPath $ExportDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]in_progress[\\/]' }
    foreach ($jsonFile in $jsonFiles) {
        try {
            $record = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
            $timestamp = [DateTime]::MinValue
            if ($record.timestampUtc) {
                [DateTime]::TryParse($record.timestampUtc.ToString(), [ref]$timestamp) | Out-Null
            }

            $records += [pscustomobject]@{
                File = $jsonFile
                Record = $record
                Timestamp = $timestamp
            }
        }
        catch {
            Write-Warning "Could not parse pulled questionnaire JSON: $($jsonFile.FullName)"
        }
    }

    return $records
}

function Get-ExportCounts {
    param($Record)

    if ($null -eq $Record) {
        return [ordered]@{
            foundJson = $false
            maia2Answers = $null
            maia2Scores = $null
            pictographicSelections = $null
            questionnaireAnswers = $null
            temporalTraceCount = $null
            questionnaireConfigId = $null
            participant = $null
            language = $null
        }
    }

    return [ordered]@{
        foundJson = $true
        maia2Answers = @($Record.maia2Answers).Count
        maia2Scores = @($Record.maia2Scores).Count
        pictographicSelections = @($Record.pictographicSelections).Count
        questionnaireAnswers = @($Record.questionnaireAnswers).Count
        temporalTraceCount = @($Record.temporalTraces).Count
        questionnaireConfigId = $Record.questionnaireConfigId
        participant = $Record.participant.name
        language = $Record.participant.language
    }
}

function Get-ExpectedCounts {
    param([string]$ProjectPath)

    $runtimeConfigPath = Join-Path $ProjectPath 'app\src\main\assets\questionnaire\QuestionnaireConfig.json'
    if (-not (Test-Path -LiteralPath $runtimeConfigPath)) {
        return [ordered]@{ maia2Answers = 37; maia2Scores = 8; pictographicSelections = 3; questionnaireAnswers = 42; temporalTraceCount = 0 }
    }

    $runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json
    $maiaBlock = @($runtimeConfig.blocks | Where-Object { $_.id -eq 'maia2' } | Select-Object -First 1)[0]
    $pictographicBlock = @($runtimeConfig.blocks | Where-Object { $_.type -eq 'pictographic' } | Select-Object -First 1)[0]
    $sliderBlock = @($runtimeConfig.blocks | Where-Object { $_.type -eq 'slider' } | Select-Object -First 1)[0]
    $temporalBlock = @($runtimeConfig.blocks | Where-Object { $_.id -eq 'temporal_tracer' -or $_.type -eq 'temporalTracer' } | Select-Object -First 1)[0]

    return [ordered]@{
        maia2Answers = if ($maiaBlock) { [int]$maiaBlock.expectedItemCount } else { 0 }
        maia2Scores = if ($maiaBlock) { 8 } else { 0 }
        pictographicSelections = if ($pictographicBlock) { @($pictographicBlock.prompts).Count } else { 0 }
        questionnaireAnswers = if ($sliderBlock) { [int]$sliderBlock.expectedItemCount } else { 0 }
        temporalTraceCount = if ($temporalBlock) { @($temporalBlock.dimensions).Count } else { 0 }
    }
}

function ConvertTo-DrawingColor {
    param(
        [string]$Hex,
        [int]$Alpha = 255
    )

    if ([string]::IsNullOrWhiteSpace($Hex)) {
        return [System.Drawing.Color]::FromArgb($Alpha, 255, 255, 255)
    }

    $value = $Hex.Trim().TrimStart('#')
    return [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($value.Substring(0, 2), 16),
        [Convert]::ToInt32($value.Substring(2, 2), 16),
        [Convert]::ToInt32($value.Substring(4, 2), 16))
}

function Get-DrawRect {
    param($Bounds)

    return [System.Drawing.RectangleF]::new(
        [float]$Bounds.left,
        [float]$Bounds.top,
        [float]$Bounds.width,
        [float]$Bounds.height)
}

function New-RenderFont {
    param(
        $Node,
        [switch]$Bold
    )

    $size = 15.0
    if ($Node.PSObject.Properties.Name -contains 'textSize') {
        $size = [Math]::Max(7.5, [double]$Node.textSize * 0.75)
    }
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return [System.Drawing.Font]::new('Segoe UI', [single]$size, $style, [System.Drawing.GraphicsUnit]::Point)
}

function Draw-WrappedText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$Brush,
        [System.Drawing.RectangleF]$Rect,
        [int]$Gravity = 3
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $horizontalGravity = $Gravity -band 7
    $lineHeight = [Math]::Max(1.0, $Font.GetHeight($Graphics) + 4.0)
    $y = $Rect.Top
    foreach ($paragraph in ($Text -split "`n", -1)) {
        if ([string]::IsNullOrWhiteSpace($paragraph)) {
            $y += $lineHeight
            continue
        }

        $line = ''
        foreach ($word in ($paragraph -split '\s+')) {
            $candidate = if ($line.Length -eq 0) { $word } else { "$line $word" }
            $candidateWidth = $Graphics.MeasureString($candidate, $Font).Width
            if ($candidateWidth -le $Rect.Width -or $line.Length -eq 0) {
                $line = $candidate
            }
            else {
                Draw-TextLine -Graphics $Graphics -Text $line -Font $Font -Brush $Brush -Rect $Rect -Y $y -HorizontalGravity $horizontalGravity
                $line = $word
                $y += $lineHeight
            }
        }

        if ($line.Length -gt 0) {
            Draw-TextLine -Graphics $Graphics -Text $line -Font $Font -Brush $Brush -Rect $Rect -Y $y -HorizontalGravity $horizontalGravity
            $y += $lineHeight
        }
    }
}

function Draw-TextLine {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$Brush,
        [System.Drawing.RectangleF]$Rect,
        [float]$Y,
        [int]$HorizontalGravity
    )

    $width = $Graphics.MeasureString($Text, $Font).Width
    $x = $Rect.Left
    if ($HorizontalGravity -eq 5) {
        $x = $Rect.Left + [Math]::Max(0, $Rect.Width - $width)
    }
    elseif ($HorizontalGravity -eq 1) {
        $x = $Rect.Left + [Math]::Max(0, ($Rect.Width - $width) / 2.0)
    }
    $Graphics.DrawString($Text, $Font, $Brush, [single]$x, [single]$Y)
}

function Paint-RenderNode {
    param(
        [System.Drawing.Graphics]$Graphics,
        $Node,
        [string]$ProjectPath
    )

    if ($null -eq $Node -or $Node.visible -eq $false) {
        return
    }

    $rect = Get-DrawRect -Bounds $Node.bounds
    if ($rect.Width -le 0 -or $rect.Height -le 0) {
        return
    }

    if ($Node.backgroundColor) {
        $brush = [System.Drawing.SolidBrush]::new((ConvertTo-DrawingColor -Hex $Node.backgroundColor -Alpha $(if ($Node.enabled -eq $false) { 150 } else { 255 })))
        try { $Graphics.FillRectangle($brush, $rect) } finally { $brush.Dispose() }
    }

    switch ($Node.className) {
        'RadioButton' { Paint-RadioButton -Graphics $Graphics -Node $Node -Rect $rect; break }
        'CheckBox' { Paint-CheckBox -Graphics $Graphics -Node $Node -Rect $rect; break }
        'Button' { Paint-Button -Graphics $Graphics -Node $Node -Rect $rect; break }
        'EditText' { Paint-EditText -Graphics $Graphics -Node $Node -Rect $rect; break }
        'SeekBar' { Paint-SeekBar -Graphics $Graphics -Node $Node -Rect $rect; break }
        'TraceCanvasView' { Paint-TraceCanvasView -Graphics $Graphics -Rect $rect; break }
        'ImageView' { Paint-ImageView -Graphics $Graphics -Node $Node -Rect $rect -ProjectPath $ProjectPath; break }
        'TextView' { Paint-TextView -Graphics $Graphics -Node $Node -Rect $rect; break }
    }

    $children = @($Node.children)
    if ($children.Count -gt 0 -and $null -ne $children[0]) {
        $state = $Graphics.Save()
        try {
            if ($Node.className -eq 'ScrollView') {
                $Graphics.SetClip($rect)
            }
            foreach ($child in $children) {
                Paint-RenderNode -Graphics $Graphics -Node $child -ProjectPath $ProjectPath
            }
        }
        finally {
            $Graphics.Restore($state)
        }
    }
}

function Paint-TextView {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect)

    $text = [string]$Node.text
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $font = New-RenderFont -Node $Node
    $brush = [System.Drawing.SolidBrush]::new((ConvertTo-DrawingColor -Hex $Node.textColor -Alpha $(if ($Node.enabled -eq $false) { 155 } else { 255 })))
    try {
        $textRect = [System.Drawing.RectangleF]::new(
            $Rect.Left + [float]$Node.paddingLeft,
            $Rect.Top + [float]$Node.paddingTop,
            [Math]::Max(1.0, $Rect.Width - [float]$Node.paddingLeft - [float]$Node.paddingRight),
            [Math]::Max(1.0, $Rect.Height - [float]$Node.paddingTop - [float]$Node.paddingBottom))
        Draw-WrappedText -Graphics $Graphics -Text $text -Font $font -Brush $brush -Rect $textRect -Gravity ([int]$Node.gravity)
    }
    finally {
        $brush.Dispose()
        $font.Dispose()
    }
}

function Paint-EditText {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect)

    $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(150, 158, 172), 1)
    try {
        $Graphics.FillRectangle($fill, $Rect)
        $Graphics.DrawRectangle($pen, $Rect.X, $Rect.Y, $Rect.Width, $Rect.Height)
    }
    finally {
        $fill.Dispose()
        $pen.Dispose()
    }

    $text = [string]$Node.text
    $showingHint = $false
    if ([string]::IsNullOrEmpty($text) -and $Node.hint) {
        $text = [string]$Node.hint
        $showingHint = $true
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $font = New-RenderFont -Node $Node
    $color = if ($showingHint) { [System.Drawing.Color]::FromArgb(90, 96, 108) } else { ConvertTo-DrawingColor -Hex $Node.textColor }
    $brush = [System.Drawing.SolidBrush]::new($color)
    try {
        $y = $Rect.Top + [Math]::Max(0, ($Rect.Height - $font.GetHeight($Graphics)) / 2.0)
        $Graphics.DrawString($text, $font, $brush, [single]($Rect.Left + [float]$Node.paddingLeft), [single]$y)
    }
    finally {
        $brush.Dispose()
        $font.Dispose()
    }
}

function Paint-Button {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect)

    if ($Node.enabled -eq $false) {
        $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(82, 88, 102))
        try { $Graphics.FillRectangle($fill, $Rect) } finally { $fill.Dispose() }
    }

    $font = New-RenderFont -Node $Node -Bold
    $brush = [System.Drawing.SolidBrush]::new((ConvertTo-DrawingColor -Hex $Node.textColor -Alpha $(if ($Node.enabled -eq $false) { 145 } else { 255 })))
    $format = [System.Drawing.StringFormat]::new()
    try {
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $Graphics.DrawString([string]$Node.text, $font, $brush, $Rect, $format)
    }
    finally {
        $format.Dispose()
        $brush.Dispose()
        $font.Dispose()
    }
}

function Paint-RadioButton {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect)

    $size = [Math]::Min(24.0, [Math]::Max(18.0, $Rect.Height / 2.0))
    $x = $Rect.Left + [float]$Node.paddingLeft + 8.0
    $y = $Rect.Top + ($Rect.Height - $size) / 2.0
    $pen = [System.Drawing.Pen]::new((ConvertTo-DrawingColor -Hex '#F5F8FA' -Alpha $(if ($Node.enabled -eq $false) { 140 } else { 255 })), 2)
    try { $Graphics.DrawEllipse($pen, $x, $y, $size, $size) } finally { $pen.Dispose() }
    if ($Node.checked) {
        $brush = [System.Drawing.SolidBrush]::new((ConvertTo-DrawingColor -Hex '#00CFAE'))
        try { $Graphics.FillEllipse($brush, $x + 5, $y + 5, $size - 10, $size - 10) } finally { $brush.Dispose() }
    }
    Paint-CompoundText -Graphics $Graphics -Node $Node -Rect $Rect -TextLeft ($x + $size + 14.0)
}

function Paint-CheckBox {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect)

    $size = [Math]::Min(24.0, [Math]::Max(18.0, $Rect.Height / 2.0))
    $x = $Rect.Left + [float]$Node.paddingLeft + 8.0
    $y = $Rect.Top + ($Rect.Height - $size) / 2.0
    $pen = [System.Drawing.Pen]::new((ConvertTo-DrawingColor -Hex '#F5F8FA' -Alpha $(if ($Node.enabled -eq $false) { 140 } else { 255 })), 2)
    try { $Graphics.DrawRectangle($pen, $x, $y, $size, $size) } finally { $pen.Dispose() }
    if ($Node.checked) {
        $checkPen = [System.Drawing.Pen]::new((ConvertTo-DrawingColor -Hex '#00CFAE'), 3)
        try {
            $Graphics.DrawLine($checkPen, $x + 5, $y + $size / 2.0, $x + $size / 2.0, $y + $size - 5)
            $Graphics.DrawLine($checkPen, $x + $size / 2.0, $y + $size - 5, $x + $size - 4, $y + 5)
        }
        finally { $checkPen.Dispose() }
    }
    Paint-CompoundText -Graphics $Graphics -Node $Node -Rect $Rect -TextLeft ($x + $size + 14.0)
}

function Paint-CompoundText {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect, [float]$TextLeft)

    $font = New-RenderFont -Node $Node
    $brush = [System.Drawing.SolidBrush]::new((ConvertTo-DrawingColor -Hex $Node.textColor -Alpha $(if ($Node.enabled -eq $false) { 155 } else { 255 })))
    try {
        $textRect = [System.Drawing.RectangleF]::new(
            $TextLeft,
            $Rect.Top + [float]$Node.paddingTop,
            [Math]::Max(1.0, $Rect.Right - $TextLeft - [float]$Node.paddingRight),
            [Math]::Max(1.0, $Rect.Height - [float]$Node.paddingTop - [float]$Node.paddingBottom))
        Draw-WrappedText -Graphics $Graphics -Text ([string]$Node.text) -Font $font -Brush $brush -Rect $textRect -Gravity 3
    }
    finally {
        $brush.Dispose()
        $font.Dispose()
    }
}

function Paint-SeekBar {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect)

    $trackLeft = $Rect.Left + 18.0
    $trackRight = $Rect.Right - 18.0
    $trackY = $Rect.Top + $Rect.Height / 2.0
    $trackPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(96, 106, 124), 6)
    $accentPen = [System.Drawing.Pen]::new((ConvertTo-DrawingColor -Hex '#00CFAE'), 6)
    $accentBrush = [System.Drawing.SolidBrush]::new((ConvertTo-DrawingColor -Hex '#00CFAE'))
    try {
        $Graphics.DrawLine($trackPen, $trackLeft, $trackY, $trackRight, $trackY)
        $fraction = if ([int]$Node.max -eq 0) { 0.0 } else { [double]$Node.progress / [double]$Node.max }
        $knobX = $trackLeft + ($trackRight - $trackLeft) * $fraction
        $Graphics.DrawLine($accentPen, $trackLeft, $trackY, $knobX, $trackY)
        $Graphics.FillEllipse($accentBrush, $knobX - 14, $trackY - 14, 28, 28)
    }
    finally {
        $trackPen.Dispose()
        $accentPen.Dispose()
        $accentBrush.Dispose()
    }
}

function Paint-TraceCanvasView {
    param([System.Drawing.Graphics]$Graphics, [System.Drawing.RectangleF]$Rect)

    $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(18, 24, 33))
    $startBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(54, 102, 180, 232))
    $border = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(150, 169, 182, 201), 2)
    $grid = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(72, 169, 182, 201), 1)
    $axis = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(225, 245, 248, 250), 2)
    $trace = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 0, 207, 174), 4)
    try {
        $Graphics.FillRectangle($fill, $Rect)
        $plot = [System.Drawing.RectangleF]::new($Rect.Left + 56, $Rect.Top + 24, [Math]::Max(1.0, $Rect.Width - 88), [Math]::Max(1.0, $Rect.Height - 56))
        $Graphics.FillRectangle($startBrush, [System.Drawing.RectangleF]::new($Rect.Left + 8, $plot.Top, 42, $plot.Height))
        $Graphics.DrawRectangle($border, $Rect.X, $Rect.Y, $Rect.Width, $Rect.Height)
        for ($i = 0; $i -le 5; $i++) {
            $x = $plot.Left + $plot.Width * ($i / 5.0)
            $Graphics.DrawLine($grid, [single]$x, [single]$plot.Top, [single]$x, [single]$plot.Bottom)
        }
        for ($i = 0; $i -le 4; $i++) {
            $y = $plot.Top + $plot.Height * ($i / 4.0)
            $Graphics.DrawLine($grid, [single]$plot.Left, [single]$y, [single]$plot.Right, [single]$y)
        }
        $Graphics.DrawLine($axis, [single]$plot.Left, [single]$plot.Top, [single]$plot.Left, [single]$plot.Bottom)
        $Graphics.DrawLine($axis, [single]$plot.Left, [single]$plot.Bottom, [single]$plot.Right, [single]$plot.Bottom)

        $points = @(
            [System.Drawing.PointF]::new($plot.Left, $plot.Bottom - $plot.Height * 0.25),
            [System.Drawing.PointF]::new($plot.Left + $plot.Width * 0.22, $plot.Bottom - $plot.Height * 0.42),
            [System.Drawing.PointF]::new($plot.Left + $plot.Width * 0.48, $plot.Bottom - $plot.Height * 0.35),
            [System.Drawing.PointF]::new($plot.Left + $plot.Width * 0.74, $plot.Bottom - $plot.Height * 0.66),
            [System.Drawing.PointF]::new($plot.Right, $plot.Bottom - $plot.Height * 0.58)
        )
        $Graphics.DrawLines($trace, $points)
    }
    finally {
        $fill.Dispose()
        $startBrush.Dispose()
        $border.Dispose()
        $grid.Dispose()
        $axis.Dispose()
        $trace.Dispose()
    }
}

function Paint-ImageView {
    param([System.Drawing.Graphics]$Graphics, $Node, [System.Drawing.RectangleF]$Rect, [string]$ProjectPath)

    if (-not $Node.asset) { return }
    $assetPath = Join-Path $ProjectPath ("app\src\main\assets\questionnaire\PictographicScales\" + [string]$Node.asset)
    if (-not (Test-Path -LiteralPath $assetPath)) { return }

    $image = [System.Drawing.Image]::FromFile($assetPath)
    try {
        $availableWidth = [Math]::Max(1.0, $Rect.Width - [float]$Node.paddingLeft - [float]$Node.paddingRight)
        $availableHeight = [Math]::Max(1.0, $Rect.Height - [float]$Node.paddingTop - [float]$Node.paddingBottom)
        $scale = [Math]::Min($availableWidth / $image.Width, $availableHeight / $image.Height)
        $drawWidth = [Math]::Max(1.0, $image.Width * $scale)
        $drawHeight = [Math]::Max(1.0, $image.Height * $scale)
        $x = $Rect.Left + [float]$Node.paddingLeft + ($availableWidth - $drawWidth) / 2.0
        $y = $Rect.Top + [float]$Node.paddingTop + ($availableHeight - $drawHeight) / 2.0
        $Graphics.DrawImage($image, [System.Drawing.RectangleF]::new($x, $y, $drawWidth, $drawHeight))
    }
    finally {
        $image.Dispose()
    }
}

function Update-RenderPngsFromLayouts {
    param(
        $RenderSummary,
        [string]$ProjectPath
    )

    Add-Type -AssemblyName System.Drawing
    foreach ($render in @($RenderSummary.renders)) {
        if (-not $render.layout -or -not (Test-Path -LiteralPath $render.layout)) {
            continue
        }

        $tree = Get-Content -LiteralPath $render.layout -Raw | ConvertFrom-Json
        $bitmap = [System.Drawing.Bitmap]::new([int]$render.widthDp, [int]$render.heightDp)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            Paint-RenderNode -Graphics $graphics -Node $tree -ProjectPath $ProjectPath
            $bitmap.Save($render.png, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }

        $render.byteLength = (Get-Item -LiteralPath $render.png).Length
        $render.sha256 = (Get-FileHash -LiteralPath $render.png -Algorithm SHA256).Hash.ToLowerInvariant()
        $render | Add-Member -NotePropertyName hostRenderer -NotePropertyValue 'system-drawing-layout-json' -Force
    }

    $RenderSummary.renderer = 'robolectric-android-layout-system-drawing'
    $RenderSummary | Add-Member -NotePropertyName hostRenderUpdatedAt -NotePropertyValue (Get-Date).ToString('o') -Force
}

function Test-ForegroundEvidence {
    param(
        [string]$AdbPath,
        [string]$RequestedSerial,
        [string]$RunOutDir,
        [bool]$LaunchBeforeCheck
    )

    $evidenceDir = Join-Path $RunOutDir 'quest-foreground'
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    $deviceSerial = Resolve-Serial -AdbPath $AdbPath -RequestedSerial $RequestedSerial -EvidenceDir $evidenceDir
    $launchExitCode = $null
    if ($LaunchBeforeCheck) {
        $launchPath = Join-Path $evidenceDir 'launch-before-foreground-check.txt'
        $launchExitCode = Invoke-AdbText -AdbPath $AdbPath -DeviceSerial $deviceSerial -Arguments @('shell', 'am', 'start', '-n', "$package/$activity") -OutputPath $launchPath
        Start-Sleep -Seconds 2
    }

    $foregroundPath = Join-Path $evidenceDir 'foreground.txt'
    $activityPath = Join-Path $evidenceDir 'activity-activities.txt'
    $pidPath = Join-Path $evidenceDir 'pidof.txt'
    $logPath = Join-Path $evidenceDir 'logcat.txt'
    $taggedLogPath = Join-Path $evidenceDir 'logcat-myquestionnaire2d.txt'
    Invoke-AdbText -AdbPath $AdbPath -DeviceSerial $deviceSerial -Arguments @('shell', 'dumpsys', 'window') -OutputPath $foregroundPath | Out-Null
    Invoke-AdbText -AdbPath $AdbPath -DeviceSerial $deviceSerial -Arguments @('shell', 'dumpsys', 'activity', 'activities') -OutputPath $activityPath | Out-Null
    Invoke-AdbText -AdbPath $AdbPath -DeviceSerial $deviceSerial -Arguments @('shell', 'pidof', $package) -OutputPath $pidPath | Out-Null
    Invoke-AdbText -AdbPath $AdbPath -DeviceSerial $deviceSerial -Arguments @('logcat', '-d', '-v', 'threadtime') -OutputPath $logPath | Out-Null
    Invoke-AdbText -AdbPath $AdbPath -DeviceSerial $deviceSerial -Arguments @('logcat', '-d', '-v', 'threadtime', 'MyQuestionnaire2D:I', 'AndroidRuntime:E', '*:S') -OutputPath $taggedLogPath | Out-Null

    $exportOut = Join-Path $evidenceDir 'exports'
    $resolvedEvidenceDir = [System.IO.Path]::GetFullPath($evidenceDir)
    $resolvedExportOut = [System.IO.Path]::GetFullPath($exportOut)
    if (-not $resolvedExportOut.StartsWith($resolvedEvidenceDir, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean export pull directory outside foreground evidence directory: $resolvedExportOut"
    }
    if (Test-Path -LiteralPath $exportOut) {
        Remove-Item -LiteralPath $exportOut -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $exportOut | Out-Null

    $pullStdout = Join-Path $evidenceDir 'pull-device-exports-stdout.txt'
    $pullStderr = Join-Path $evidenceDir 'pull-device-exports-stderr.txt'
    $pullProcess = Start-Process -FilePath $AdbPath -ArgumentList @('-s', $deviceSerial, 'pull', $deviceExports, $exportOut) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $pullStdout -RedirectStandardError $pullStderr
    $pullExitCode = $pullProcess.ExitCode

    $foregroundText = if (Test-Path -LiteralPath $foregroundPath) { Get-Content -LiteralPath $foregroundPath -Raw } else { "" }
    $activityText = if (Test-Path -LiteralPath $activityPath) { Get-Content -LiteralPath $activityPath -Raw } else { "" }
    $focusLines = @(
        $foregroundText -split "`r?`n" | Where-Object { $_ -match 'mCurrentFocus|mFocusedApp|mFocusedWindow|mResumedActivity|WindowState|visible=true|questionnaires2d|MainActivity' }
        $activityText -split "`r?`n" | Where-Object { $_ -match 'topResumedActivity|ResumedActivity|state=RESUMED|visible=true|VisibleActivityProcess|questionnaires2d|MainActivity' }
    )
    $pidText = if (Test-Path -LiteralPath $pidPath) { (Get-Content -LiteralPath $pidPath -Raw).Trim() } else { "" }
    $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { "" }
    if (Test-Path -LiteralPath $taggedLogPath) {
        $logText += "`n" + (Get-Content -LiteralPath $taggedLogPath -Raw)
    }

    $records = @(Get-ExportRecords -ExportDir $exportOut | Sort-Object -Property Timestamp -Descending)
    $selectedRecord = if ($records.Count -gt 0) { $records[0] } else { $null }
    $counts = Get-ExportCounts -Record $(if ($selectedRecord) { $selectedRecord.Record } else { $null })

    $foregroundHasPackage = [bool]($focusLines -match [regex]::Escape($package))
    $foregroundHasActivity = [bool]($focusLines -match 'MainActivity')
    $pidAlive = -not [string]::IsNullOrWhiteSpace($pidText)
    $fatalLogCount = @([regex]::Matches($logText, 'FATAL EXCEPTION|\bE\s+AndroidRuntime\b')).Count
    $commandReplayStarted = [bool]($logText -match 'MYQUESTIONNAIRE_COMMAND_REPLAY_START')
    $commandReplayPassed = [bool]($logText -match 'MYQUESTIONNAIRE_NAVIGATION_SUMMARY status=pass mode=command-replay')
    $commandReplayExportMatched = [bool]($logText -match 'MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH')
    $exportCompleteLogged = [bool]($logText -match 'MYQUESTIONNAIRE_EXPORT_COMPLETE')
    $commandEventCount = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_COMMAND command=')).Count
    $visualStages = @([regex]::Matches($logText, 'MYQUESTIONNAIRE_VISUAL_STAGE stage=([a-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $expectedCounts = Get-ExpectedCounts -ProjectPath $ProjectPath
    $requiredVisualStages = @('language', 'demographics')
    if ($expectedCounts.maia2Answers -gt 0) { $requiredVisualStages += 'maia2' }
    if ($expectedCounts.pictographicSelections -gt 0) { $requiredVisualStages += 'pictographic' }
    if ($expectedCounts.questionnaireAnswers -gt 0) { $requiredVisualStages += 'slider' }
    if ($expectedCounts.temporalTraceCount -gt 0) { $requiredVisualStages += 'temporal-tracer' }
    $requiredVisualStages += @('saved-confirmation', 'finished-black')
    $visualStageReplayPassed = $true
    foreach ($requiredStage in $requiredVisualStages) {
        if (-not ($visualStages -contains $requiredStage)) {
            $visualStageReplayPassed = $false
        }
    }
    $escapedPackage = [regex]::Escape($package)
    $targetActivityResumed =
        [regex]::IsMatch($activityText, "topResumedActivity=ActivityRecord\{[^\r\n]*$escapedPackage[^\r\n]*MainActivity") -or
        [regex]::IsMatch($activityText, "ActivityRecord\{[^\r\n]*$escapedPackage[^\r\n]*MainActivity[\s\S]{0,2000}?state=RESUMED") -or
        [regex]::IsMatch($activityText, "(?:Resumed|ResumedActivity|mFocusedApp)\s*[:=]\s*ActivityRecord\{[^\r\n]*$escapedPackage[^\r\n]*MainActivity")

    $exportCountsPass =
        $counts.foundJson -and
        $counts.maia2Answers -eq $expectedCounts.maia2Answers -and
        $counts.maia2Scores -eq $expectedCounts.maia2Scores -and
        $counts.pictographicSelections -eq $expectedCounts.pictographicSelections -and
        $counts.questionnaireAnswers -eq $expectedCounts.questionnaireAnswers -and
        $counts.temporalTraceCount -eq $expectedCounts.temporalTraceCount

    $foregroundPass =
        $foregroundHasPackage -and
        $foregroundHasActivity -and
        $targetActivityResumed -and
        $pidAlive -and
        $fatalLogCount -eq 0 -and
        $commandReplayStarted -and
        $commandReplayPassed -and
        $commandReplayExportMatched -and
        $exportCompleteLogged -and
        $visualStageReplayPassed -and
        $commandEventCount -ge 8 -and
        $exportCountsPass

    $summary = [ordered]@{
        schemaVersion = 'my-questionnaire-2d.quest-foreground-check.v1'
        status = if ($foregroundPass) { 'pass' } else { 'fail' }
        serial = $deviceSerial
        package = $package
        activity = $activity
        evidenceDir = $evidenceDir
        launchBeforeForegroundCheck = $LaunchBeforeCheck
        launchExitCode = $launchExitCode
        foregroundHasPackage = $foregroundHasPackage
        foregroundHasActivity = $foregroundHasActivity
        targetActivityResumed = $targetActivityResumed
        focusLines = @($focusLines)
        pidAlive = $pidAlive
        pidText = $pidText
        fatalLogCount = $fatalLogCount
        commandReplayStarted = $commandReplayStarted
        commandReplayPassed = $commandReplayPassed
        commandReplayExportMatched = $commandReplayExportMatched
        exportCompleteLogged = $exportCompleteLogged
        commandEventCount = $commandEventCount
        visualStages = $visualStages
        visualStageReplayPassed = $visualStageReplayPassed
        pullExitCode = $pullExitCode
        exportCountsPass = $exportCountsPass
        expectedCounts = $expectedCounts
        latestJson = if ($selectedRecord) { $selectedRecord.File.FullName } else { $null }
        exportCounts = $counts
        checkedAt = (Get-Date).ToString('o')
    }

    $summaryPath = Join-Path $evidenceDir 'quest-foreground-check.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return $summary
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "render-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath 'artifacts\questionnaire-render-validation'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

$runOutDir = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force -Path $runOutDir | Out-Null

$resolvedConfigPath = ""
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config not found: $ConfigPath"
    }
    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
}

if (-not $SkipAssetRefresh) {
    if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
        $validateConfigScript = Join-Path $ProjectPath 'tools\validate-questionnaire-config.ps1'
        & $validateConfigScript `
            -ConfigPath $resolvedConfigPath `
            -ReferenceProjectPath $ReferenceProjectPath | Out-Host
    }

    $applyScript = Join-Path $ProjectPath 'tools\apply-questionnaire-config.ps1'
    $validateAssetsScript = Join-Path $ProjectPath 'tools\validate-questionnaire-assets.ps1'
    if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
        & $applyScript -ConfigPath $resolvedConfigPath -ReferenceProjectPath $ReferenceProjectPath | Out-Host
    }
    else {
        & $applyScript -ReferenceProjectPath $ReferenceProjectPath | Out-Host
    }
    & $validateAssetsScript | Out-Host
}

$foregroundSummary = $null
if ($CheckQuestForeground -or $RequireQuestForeground) {
    $resolvedAdb = Resolve-Adb -RequestedAdb $Adb
    $foregroundSummary = Test-ForegroundEvidence `
        -AdbPath $resolvedAdb `
        -RequestedSerial $Serial `
        -RunOutDir $runOutDir `
        -LaunchBeforeCheck ([bool]$LaunchBeforeForegroundCheck)
}

$javaHome = Join-Path $UnityAndroidRoot 'OpenJDK'
$sdk = Join-Path $UnityAndroidRoot 'SDK'
if (-not (Test-Path -LiteralPath (Join-Path $javaHome 'bin\java.exe'))) {
    throw "Unity OpenJDK not found under: $javaHome"
}
if (-not (Test-Path -LiteralPath $sdk)) {
    throw "Unity Android SDK not found under: $sdk"
}

$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:UNITY_ANDROID_ROOT = $UnityAndroidRoot

$localProperties = Join-Path $ProjectPath 'local.properties'
$sdkForward = $sdk -replace '\\', '/'
[System.IO.File]::WriteAllText($localProperties, "sdk.dir=$sdkForward`n", [System.Text.UTF8Encoding]::new($false))

Push-Location $ProjectPath
try {
    $gradle = Join-Path $ProjectPath 'gradlew.bat'
    $gradleArgs = @(
        '--no-daemon',
        "-Dquestionnaire.render.enabled=true",
        "-Dquestionnaire.render.outputDir=$runOutDir",
        "-Dquestionnaire.render.sizes=$Sizes",
        "-Dquestionnaire.render.runId=$RunId",
        'testDebugUnitTest',
        '--rerun-tasks'
    )
    Invoke-GradleRender -GradlePath $gradle -Arguments $gradleArgs
}
finally {
    Pop-Location
}

$renderSummaryPath = Join-Path $runOutDir 'render-summary.json'
if (-not (Test-Path -LiteralPath $renderSummaryPath)) {
    throw "Expected render summary not found: $renderSummaryPath"
}

$renderSummary = Get-Content -LiteralPath $renderSummaryPath -Raw | ConvertFrom-Json
Update-RenderPngsFromLayouts -RenderSummary $renderSummary -ProjectPath $ProjectPath
$renderSummary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $renderSummaryPath -Encoding UTF8
$expected = $renderSummary.expectedCounts
$sliderCount = if ($expected.PSObject.Properties.Name -contains 'custom_slider') {
    [int]$expected.custom_slider
}
elseif ($expected.PSObject.Properties.Name -contains 'questquestionnaire') {
    [int]$expected.questquestionnaire
}
else {
    -1
}
$temporalCount = if ($expected.PSObject.Properties.Name -contains 'temporalTracer') {
    [int]$expected.temporalTracer
}
else {
    0
}
if ($expected.maia2 -lt 0 -or $expected.pictographic -lt 0 -or $sliderCount -lt 0 -or $temporalCount -lt 0) {
    throw "Render metadata count mismatch. See $renderSummaryPath"
}

$renderFailures = @($renderSummary.renders | Where-Object { $_.status -eq 'fail' })
$renderWarnings = @($renderSummary.renders | Where-Object { $_.status -eq 'warn' })
if ($renderFailures.Count -gt 0) {
    throw "Render validation found $($renderFailures.Count) failing screen(s). See $renderSummaryPath"
}

if ($RequireQuestForeground -and $foregroundSummary -and $foregroundSummary.status -ne 'pass') {
    throw "Quest foreground gate failed. See $($foregroundSummary.evidenceDir)\quest-foreground-check.json"
}

$hostSummary = [ordered]@{
    schemaVersion = 'my-questionnaire-2d.render-wrapper.v1'
    status = if ($foregroundSummary -and $foregroundSummary.status -ne 'pass') { 'warn' } else { 'pass' }
    runId = $RunId
    configPath = if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath)) { $resolvedConfigPath } else { $null }
    artifactDir = $runOutDir
    renderSummary = $renderSummaryPath
    renderCount = @($renderSummary.renders).Count
    renderWarningCount = $renderWarnings.Count
    questForeground = $foregroundSummary
    completedAt = (Get-Date).ToString('o')
}

$hostSummaryPath = Join-Path $runOutDir 'render-wrapper-summary.json'
$hostSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hostSummaryPath -Encoding UTF8

Write-Host "Android render validation artifacts written to $runOutDir"
Write-Host "Render summary: $renderSummaryPath"
if ($foregroundSummary) {
    Write-Host "Quest foreground summary: $($foregroundSummary.evidenceDir)\quest-foreground-check.json"
}
Write-Host "Render warnings: $($renderWarnings.Count)"
