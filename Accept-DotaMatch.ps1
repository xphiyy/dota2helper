param(
    [int]$PollMs = 450,
    [int]$StableHits = 3,
    [int]$CooldownSeconds = 15,
    [int]$DurationSeconds = 0,
    [switch]$Calibrate,
    [switch]$StopAfterAccept,
    [switch]$NoClick,
    [switch]$AllowAnyForeground,
    [switch]$VerboseDetection,
    [string]$LogPath = ''
)

$configPath = Join-Path $PSScriptRoot 'acceptor.config.json'

function Write-Status {
    param([string]$Message)
    Write-Host $Message
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        try {
            $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
            Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
        }
        catch {
            # Logging should never stop the detector.
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
    return $title -match 'Dota\s*2'
}

function New-CenterScanRegion {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $scale = [Math]::Max(0.75, [Math]::Min(1.6, $screen.Height / 1080.0))

    $width = [int][Math]::Min($screen.Width * 0.42, 520 * $scale)
    $height = [int](150 * $scale)
    $x = [int](($screen.Width - $width) / 2)

    # popup_accept_match.vcss_c places the 320x64 accept button centered,
    # roughly below the screen center inside a 768px-wide popup panel.
    $y = [int](($screen.Height / 2) - (35 * $scale))

    [System.Drawing.Rectangle]::new($x, $y, $width, $height)
}

function Get-AcceptButtonCandidate {
    param([System.Drawing.Rectangle]$Region)

    $bitmap = New-Object System.Drawing.Bitmap $Region.Width, $Region.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CopyFromScreen($Region.Location, [System.Drawing.Point]::Empty, $Region.Size)

        $step = 4
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
                    $pixel.R -ge 25 -and $pixel.R -le 115 -and
                    $pixel.G -ge 70 -and $pixel.G -le 230 -and
                    $pixel.B -ge 45 -and $pixel.B -le 165 -and
                    $pixel.G -gt ($pixel.R * 1.20) -and
                    $pixel.G -gt ($pixel.B * 0.95)

                if ($isAcceptGreen) {
                    $hits++
                    if ($x -lt $minX) { $minX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }

        if ($hits -lt 120) {
            return $null
        }

        $clusterWidth = $maxX - $minX
        $clusterHeight = $maxY - $minY

        if ($clusterWidth -lt 150 -or $clusterHeight -lt 24) {
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




