param(
    [string]$Tool = 'CreateLobby',
    [string]$OutputPath = '',
    [string]$ModGameName = 'Configured Mod Game',
    [string]$LogPath = ''
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$localDir = Join-Path $projectRoot 'local'
$captureDir = Join-Path $localDir 'captures'
[void][System.IO.Directory]::CreateDirectory($localDir)
[void][System.IO.Directory]::CreateDirectory($captureDir)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $localDir ("{0}.recorded.sequence.json" -f $Tool.ToLowerInvariant())
}

function Write-Status {
    param([string]$Message)
    Write-Host $Message
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $stream = $null
        $writer = $null
        try {
            $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $LogPath))
            $stream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
            $writer.WriteLine($line)
        }
        catch {
            # Logging should never stop recording.
        }
        finally {
            if ($null -ne $writer) { $writer.Dispose() }
            elseif ($null -ne $stream) { $stream.Dispose() }
        }
    }
}

function Read-IntOrDefault {
    param(
        [string]$Prompt,
        [int]$Default
    )

    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed)) { return $parsed }
    return $Default
}

function New-CaptureStep {
    param(
        [string]$Name,
        [int]$Width,
        [int]$Height
    )

    $cursor = [System.Windows.Forms.Cursor]::Position
    $x = [Math]::Max(0, [int]($cursor.X - ($Width / 2)))
    $y = [Math]::Max(0, [int]($cursor.Y - ($Height / 2)))
    $fileName = ("{0:yyyyMMdd-HHmmss}-{1}.png" -f (Get-Date), ($Name -replace '[^\w\-]+', '-')).Trim('-')
    if (-not $fileName.EndsWith('.png')) { $fileName = "$fileName.png" }
    $output = Join-Path $captureDir $fileName

    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([System.Drawing.Point]::new($x, $y), [System.Drawing.Point]::Empty, [System.Drawing.Size]::new($Width, $Height))
        $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    [ordered]@{
        name = $Name
        action = 'capture'
        region = [ordered]@{
            x = $x
            y = $y
            width = $Width
            height = $Height
        }
        output = $output.Replace($projectRoot + '\', '')
    }
}

function New-VerifyColorStep {
    param(
        [string]$Name,
        [int]$Width,
        [int]$Height
    )

    $cursor = [System.Windows.Forms.Cursor]::Position
    $x = [Math]::Max(0, [int]($cursor.X - ($Width / 2)))
    $y = [Math]::Max(0, [int]($cursor.Y - ($Height / 2)))
    $bitmap = New-Object System.Drawing.Bitmap 1, 1
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($cursor, [System.Drawing.Point]::Empty, [System.Drawing.Size]::new(1, 1))
        $pixel = $bitmap.GetPixel(0, 0)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    [ordered]@{
        name = $Name
        action = 'verifyColorCluster'
        region = [ordered]@{
            x = $x
            y = $y
            width = $Width
            height = $Height
        }
        color = [ordered]@{
            r = $pixel.R
            g = $pixel.G
            b = $pixel.B
        }
        tolerance = 24
        minHits = 20
        sampleStep = 4
        timeoutMs = 3000
    }
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$steps = New-Object System.Collections.Generic.List[object]
$pendingPrerequisites = New-Object System.Collections.Generic.List[object]

function Add-RecordedStep {
    param([hashtable]$Step)

    if ($pendingPrerequisites.Count -gt 0) {
        $Step.prerequisites = @($pendingPrerequisites)
        $pendingPrerequisites.Clear()
    }

    $steps.Add($Step)
}

Write-Status "Recording sequence for $Tool"
Write-Status "Output: $OutputPath"
Write-Status "Commands:"
Write-Status "  click       record current mouse position as a click"
Write-Status "  wait        record a wait in milliseconds"
Write-Status "  text        record text or a placeholder like {{ModGameName}}"
Write-Status "  keys        record SendKeys syntax"
Write-Status "  capture     capture a region around the cursor for later verification"
Write-Status "  verify      record a color-cluster verification around the cursor"
Write-Status "  prereq      record a verification prerequisite for the next operation"
Write-Status "  save        write JSON and exit"
Write-Status "  quit        exit without saving"

while ($true) {
    $command = (Read-Host 'record').Trim().ToLowerInvariant()

    switch ($command) {
        'click' {
            $name = Read-Host 'Step name'
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Click' }
            $position = [System.Windows.Forms.Cursor]::Position
            Add-RecordedStep ([ordered]@{
                name = $name
                action = 'click'
                x = $position.X
                y = $position.Y
            })
            Write-Status "Added click at $($position.X),$($position.Y)"
        }
        'wait' {
            $ms = Read-IntOrDefault -Prompt 'Milliseconds' -Default 500
            Add-RecordedStep ([ordered]@{
                name = "Wait $ms ms"
                action = 'wait'
                milliseconds = $ms
            })
            Write-Status "Added wait: $ms ms"
        }
        'text' {
            $name = Read-Host 'Step name'
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Type text' }
            $text = Read-Host 'Text'
            Add-RecordedStep ([ordered]@{
                name = $name
                action = 'text'
                text = $text
            })
            Write-Status 'Added text step'
        }
        'keys' {
            $name = Read-Host 'Step name'
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Send keys' }
            $keys = Read-Host 'SendKeys value'
            Add-RecordedStep ([ordered]@{
                name = $name
                action = 'sendKeys'
                keys = $keys
            })
            Write-Status 'Added keys step'
        }
        'capture' {
            $name = Read-Host 'Step name'
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Capture verification region' }
            $width = Read-IntOrDefault -Prompt 'Region width' -Default 320
            $height = Read-IntOrDefault -Prompt 'Region height' -Default 180
            Add-RecordedStep (New-CaptureStep -Name $name -Width $width -Height $height)
            Write-Status 'Added capture step'
        }
        'verify' {
            $name = Read-Host 'Step name'
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Verify visual state' }
            $width = Read-IntOrDefault -Prompt 'Region width' -Default 240
            $height = Read-IntOrDefault -Prompt 'Region height' -Default 120
            Add-RecordedStep (New-VerifyColorStep -Name $name -Width $width -Height $height)
            Write-Status 'Added verifyColorCluster step'
        }
        'prereq' {
            $name = Read-Host 'Prerequisite name'
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Verify current page' }
            $width = Read-IntOrDefault -Prompt 'Region width' -Default 240
            $height = Read-IntOrDefault -Prompt 'Region height' -Default 120
            $pendingPrerequisites.Add((New-VerifyColorStep -Name $name -Width $width -Height $height))
            Write-Status 'Added prerequisite for the next operation'
        }
        'save' {
            $sequence = [ordered]@{
                tool = $Tool
                modGameName = $ModGameName
                screenWidth = $screen.Width
                screenHeight = $screen.Height
                recordedAt = (Get-Date).ToString('o')
                notes = 'Generated by Record-DotaSequence.ps1. Review coordinates before running.'
                steps = $steps
            }
            if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
                $OutputPath = Join-Path $projectRoot $OutputPath
            }
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath))
            $sequence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
            Write-Status "Saved sequence: $OutputPath"
            return
        }
        'quit' {
            Write-Status 'Recording discarded.'
            return
        }
        default {
            Write-Status 'Unknown command. Use click, wait, text, keys, capture, verify, prereq, save, or quit.'
        }
    }
}
