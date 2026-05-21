param(
    [int]$PollMs = -1,
    [int]$StableHits = -1,
    [int]$CooldownSeconds = -1,
    [int]$DurationSeconds = 0,
    [switch]$Calibrate,
    [switch]$StopAfterAccept,
    [switch]$NoClick,
    [switch]$AllowAnyForeground,
    [switch]$VerboseDetection,
    [string]$ToolConfigPath = '',
    [string]$TargetConfigPath = '',
    [string]$LogPath = ''
)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$localDir = Join-Path $projectRoot 'local'
[void][System.IO.Directory]::CreateDirectory($localDir)
$configPath = Join-Path $localDir 'acceptor.config.json'
$defaultToolConfigPath = Join-Path $projectRoot 'config\tools\auto-accept.tool.json'
$defaultTargetConfigPath = Join-Path $projectRoot 'config\targets\dota-default.targets.json'

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
            # Logging should never stop the detector.
        }
        finally {
            if ($null -ne $writer) { $writer.Dispose() }
            elseif ($null -ne $stream) { $stream.Dispose() }
        }
    }
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32AcceptTool
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP = 0x0004;
}
"@

function Get-JsonConfig {
    param(
        [string]$Path,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        Write-Status "WARNING: $Label config not found: $Path"
        return $null
    }

    try {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        Write-Status "WARNING: Could not read $Label config: $Path"
        return $null
    }
}

function Get-ConfigValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default
    )

    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
        return $Object.$Name
    }

    return $Default
}

function Get-ForegroundTitle {
    $buffer = New-Object System.Text.StringBuilder 512
    $hwnd = [Win32AcceptTool]::GetForegroundWindow()
    [void][Win32AcceptTool]::GetWindowText($hwnd, $buffer, $buffer.Capacity)
    $buffer.ToString()
}

function Test-DotaForeground {
    if ($AllowAnyForeground) {
        return $true
    }

    $title = Get-ForegroundTitle
    return $title -match $script:foregroundTitlePattern
}

function New-CenterScanRegion {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $scan = Get-ConfigValue $script:acceptTarget 'scanRegion' $null

    $minScale = [double](Get-ConfigValue $scan 'minScale' 0.75)
    $maxScale = [double](Get-ConfigValue $scan 'maxScale' 1.6)
    $widthRatio = [double](Get-ConfigValue $scan 'widthRatio' 0.42)
    $maxWidthAt1080p = [double](Get-ConfigValue $scan 'maxWidthAt1080p' 520)
    $heightAt1080p = [double](Get-ConfigValue $scan 'heightAt1080p' 150)
    $yOffsetAt1080p = [double](Get-ConfigValue $scan 'yOffsetAt1080p' -35)

    $scale = [Math]::Max($minScale, [Math]::Min($maxScale, $screen.Height / 1080.0))

    $width = [int][Math]::Min($screen.Width * $widthRatio, $maxWidthAt1080p * $scale)
    $height = [int]($heightAt1080p * $scale)
    $x = [int](($screen.Width - $width) / 2)

    # popup_accept_match.vcss_c places the 320x64 accept button centered,
    # roughly below the screen center inside a 768px-wide popup panel.
    $y = [int](($screen.Height / 2) + ($yOffsetAt1080p * $scale))

    [System.Drawing.Rectangle]::new($x, $y, $width, $height)
}

function Get-AcceptButtonCandidate {
    param([System.Drawing.Rectangle]$Region)

    $bitmap = New-Object System.Drawing.Bitmap $Region.Width, $Region.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        try {
            $graphics.CopyFromScreen($Region.Location, [System.Drawing.Point]::Empty, $Region.Size)
        }
        catch {
            if ($VerboseDetection) {
                Write-Status "capture failed: $($_.Exception.Message)"
            }
            return $null
        }

        $visualRule = Get-ConfigValue $script:acceptTarget 'visualRule' $null
        $color = Get-ConfigValue $visualRule 'color' $null
        $step = [int](Get-ConfigValue $script:acceptTarget 'sampleStep' 4)
        $minHits = [int](Get-ConfigValue $visualRule 'minHits' 120)
        $minClusterWidth = [int](Get-ConfigValue $visualRule 'minClusterWidth' 150)
        $minClusterHeight = [int](Get-ConfigValue $visualRule 'minClusterHeight' 24)
        $rMin = [int](Get-ConfigValue $color 'rMin' 25)
        $rMax = [int](Get-ConfigValue $color 'rMax' 115)
        $gMin = [int](Get-ConfigValue $color 'gMin' 70)
        $gMax = [int](Get-ConfigValue $color 'gMax' 230)
        $bMin = [int](Get-ConfigValue $color 'bMin' 45)
        $bMax = [int](Get-ConfigValue $color 'bMax' 165)
        $gOverR = [double](Get-ConfigValue $color 'gOverR' 1.2)
        $gOverB = [double](Get-ConfigValue $color 'gOverB' 0.95)

        $hits = 0
        $minX = $Region.Width
        $minY = $Region.Height
        $maxX = 0
        $maxY = 0

        for ($y = 0; $y -lt $Region.Height; $y += $step) {
            for ($x = 0; $x -lt $Region.Width; $x += $step) {
                $pixel = $bitmap.GetPixel($x, $y)

                # Derived from popup_accept_match.vcss_c:
                # #Button0 uses green shades around #45715b and #48d07d.
                $isAcceptGreen =
                    $pixel.R -ge $rMin -and $pixel.R -le $rMax -and
                    $pixel.G -ge $gMin -and $pixel.G -le $gMax -and
                    $pixel.B -ge $bMin -and $pixel.B -le $bMax -and
                    $pixel.G -gt ($pixel.R * $gOverR) -and
                    $pixel.G -gt ($pixel.B * $gOverB)

                if ($isAcceptGreen) {
                    $hits++
                    if ($x -lt $minX) { $minX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }

        if ($hits -lt $minHits) {
            return $null
        }

        $clusterWidth = $maxX - $minX
        $clusterHeight = $maxY - $minY

        if ($clusterWidth -lt $minClusterWidth -or $clusterHeight -lt $minClusterHeight) {
            return $null
        }

        [pscustomobject]@{
            Hits = $hits
            X = $Region.X + [int](($minX + $maxX) / 2)
            Y = $Region.Y + [int](($minY + $maxY) / 2)
            Width = $clusterWidth
            Height = $clusterHeight
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Invoke-LeftClick {
    param([int]$X, [int]$Y)

    [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($X, $Y)
    Start-Sleep -Milliseconds 35
    [Win32AcceptTool]::mouse_event([Win32AcceptTool]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [Win32AcceptTool]::mouse_event([Win32AcceptTool]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

function Save-Calibration {
    param(
        [int]$X,
        [int]$Y,
        [System.Drawing.Rectangle]$ScanRegion
    )

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $config = [ordered]@{
        ClickX = $X
        ClickY = $Y
        ScreenWidth = $screen.Width
        ScreenHeight = $screen.Height
        ScanX = $ScanRegion.X
        ScanY = $ScanRegion.Y
        ScanWidth = $ScanRegion.Width
        ScanHeight = $ScanRegion.Height
        CreatedAt = (Get-Date).ToString('o')
    }

    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Get-Calibration {
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    try {
        Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Status "WARNING: Could not read calibration config: $configPath"
        return $null
    }
}

if ([string]::IsNullOrWhiteSpace($ToolConfigPath)) {
    $ToolConfigPath = $defaultToolConfigPath
}
if ([string]::IsNullOrWhiteSpace($TargetConfigPath)) {
    $TargetConfigPath = $defaultTargetConfigPath
}

$toolConfig = Get-JsonConfig -Path $ToolConfigPath -Label 'tool'
$targetConfig = Get-JsonConfig -Path $TargetConfigPath -Label 'target'
$defaultModeName = [string](Get-ConfigValue $toolConfig 'defaultMode' 'ready')
$defaultMode = $null
if ($null -ne $toolConfig -and $null -ne $toolConfig.modes -and $toolConfig.modes.PSObject.Properties.Name -contains $defaultModeName) {
    $defaultMode = $toolConfig.modes.$defaultModeName
}

if ($PollMs -lt 0) { $PollMs = [int](Get-ConfigValue $defaultMode 'pollMs' 450) }
if ($StableHits -lt 0) { $StableHits = [int](Get-ConfigValue $defaultMode 'stableHits' 3) }
if ($CooldownSeconds -lt 0) { $CooldownSeconds = [int](Get-ConfigValue $defaultMode 'cooldownSeconds' 15) }

$script:foregroundTitlePattern = [string](Get-ConfigValue $targetConfig 'foregroundTitlePattern' 'Dota\s*2')
$script:acceptTarget = $null
if ($null -ne $targetConfig -and $null -ne $targetConfig.targets -and $null -ne $targetConfig.targets.accept_button) {
    $script:acceptTarget = $targetConfig.targets.accept_button
}
if ($null -eq $script:acceptTarget) {
    $script:acceptTarget = [pscustomobject]@{}
}

$scanRegion = New-CenterScanRegion

if ($Calibrate) {
    Write-Status "Calibration mode"
    Write-Status "Move your mouse to the center of the real Accept button, then press Enter here."
    [void][Console]::ReadLine()

    $position = [System.Windows.Forms.Cursor]::Position
    Save-Calibration -X $position.X -Y $position.Y -ScanRegion $scanRegion
    Write-Status "Saved click coordinate: $($position.X),$($position.Y)"
    Write-Status "Config: $configPath"
    return
}

$calibration = Get-Calibration
$calibratedClick = $null
if ($null -ne $calibration) {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    if ($calibration.ScreenWidth -eq $screen.Width -and $calibration.ScreenHeight -eq $screen.Height) {
        $calibratedClick = [pscustomobject]@{
            X = [int]$calibration.ClickX
            Y = [int]$calibration.ClickY
        }
    }
    else {
        Write-Status "WARNING: Calibration was made for $($calibration.ScreenWidth)x$($calibration.ScreenHeight), current screen is $($screen.Width)x$($screen.Height). Re-run with -Calibrate."
    }
}

$hitStreak = 0
$missStreakAfterClick = 0
$clickedThisRun = $false
$lastClick = [DateTime]::MinValue
$startedAt = Get-Date

Write-Status "Dota match acceptor running. Region=$($scanRegion.X),$($scanRegion.Y),$($scanRegion.Width)x$($scanRegion.Height), PollMs=$PollMs, StableHits=$StableHits"
Write-Status "Tool config: $ToolConfigPath"
Write-Status "Target config: $TargetConfigPath"
if ($null -ne $calibratedClick) {
    Write-Status "Using calibrated click coordinate: $($calibratedClick.X),$($calibratedClick.Y)"
}
else {
    Write-Status "No calibration found. Using detected button center as click coordinate."
}
if ($StopAfterAccept) {
    Write-Status "StopAfterAccept enabled: exiting after a click and after the button disappears."
}
if ($NoClick) {
    Write-Status "NoClick mode: detections will beep/log but will not click."
}

while ($true) {
    if ($DurationSeconds -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $DurationSeconds) {
        Write-Status "Duration reached. Exiting."
        break
    }

    if (-not (Test-DotaForeground)) {
        $hitStreak = 0
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    $candidate = Get-AcceptButtonCandidate -Region $scanRegion

    if ($null -eq $candidate) {
        $hitStreak = 0

        if ($StopAfterAccept -and $clickedThisRun) {
            $missStreakAfterClick++
            if ($missStreakAfterClick -ge 3) {
                Write-Status "Accept button disappeared after click. Exiting."
                break
            }
        }

        Start-Sleep -Milliseconds $PollMs
        continue
    }

    if ($StopAfterAccept -and $clickedThisRun) {
        $missStreakAfterClick = 0
    }

    $hitStreak++
    if ($VerboseDetection) {
        Write-Status "candidate hits=$($candidate.Hits) size=$($candidate.Width)x$($candidate.Height) streak=$hitStreak at $($candidate.X),$($candidate.Y)"
    }

    $cooldownElapsed = ((Get-Date) - $lastClick).TotalSeconds -ge $CooldownSeconds
    if ($hitStreak -ge $StableHits -and $cooldownElapsed -and -not ($StopAfterAccept -and $clickedThisRun)) {
        $lastClick = Get-Date
        $hitStreak = 0
        $clickedThisRun = $true
        $missStreakAfterClick = 0

        if ($NoClick) {
            [Console]::Beep(880, 120)
            if ($null -ne $calibratedClick) {
                Write-Status "Accept button detected. Calibrated click would be $($calibratedClick.X),$($calibratedClick.Y)"
            }
            else {
                Write-Status "Accept button detected at $($candidate.X),$($candidate.Y)"
            }
        }
        else {
            $clickX = $candidate.X
            $clickY = $candidate.Y

            if ($null -ne $calibratedClick) {
                $clickX = $calibratedClick.X
                $clickY = $calibratedClick.Y
            }

            Write-Status "Accept button detected. Clicking $clickX,$clickY"
            Invoke-LeftClick -X $clickX -Y $clickY
        }
    }

    Start-Sleep -Milliseconds $PollMs
}




