Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Dota2HelperWindow
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool AllowSetForegroundWindow(uint dwProcessId);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    public const int SW_RESTORE = 9;
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const int VK_LBUTTON = 0x01;
}
"@

function Focus-ExistingHelperWindow {
    $hwnd = [Dota2HelperWindow]::FindWindow($null, 'Dota 2 Helper')
    if ($hwnd -eq [IntPtr]::Zero) {
        return
    }

    if ([Dota2HelperWindow]::IsIconic($hwnd)) {
        [void][Dota2HelperWindow]::ShowWindowAsync($hwnd, [Dota2HelperWindow]::SW_RESTORE)
    }

    $foregroundHwnd = [Dota2HelperWindow]::GetForegroundWindow()
    $currentThread = [Dota2HelperWindow]::GetCurrentThreadId()
    $foregroundPid = [uint32]0
    $targetPid = [uint32]0
    $foregroundThread = [Dota2HelperWindow]::GetWindowThreadProcessId($foregroundHwnd, [ref]$foregroundPid)
    $targetThread = [Dota2HelperWindow]::GetWindowThreadProcessId($hwnd, [ref]$targetPid)

    if ($targetPid -ne 0) { [void][Dota2HelperWindow]::AllowSetForegroundWindow($targetPid) }
    if ($foregroundThread -ne 0) { [void][Dota2HelperWindow]::AttachThreadInput($currentThread, $foregroundThread, $true) }
    if ($targetThread -ne 0) { [void][Dota2HelperWindow]::AttachThreadInput($currentThread, $targetThread, $true) }

    [void][Dota2HelperWindow]::BringWindowToTop($hwnd)
    [void][Dota2HelperWindow]::SetForegroundWindow($hwnd)
    [void][Dota2HelperWindow]::SetWindowPos($hwnd, [Dota2HelperWindow]::HWND_TOPMOST, 0, 0, 0, 0, [Dota2HelperWindow]::SWP_NOMOVE -bor [Dota2HelperWindow]::SWP_NOSIZE -bor [Dota2HelperWindow]::SWP_SHOWWINDOW)
    [void][Dota2HelperWindow]::SetWindowPos($hwnd, [Dota2HelperWindow]::HWND_NOTOPMOST, 0, 0, 0, 0, [Dota2HelperWindow]::SWP_NOMOVE -bor [Dota2HelperWindow]::SWP_NOSIZE -bor [Dota2HelperWindow]::SWP_SHOWWINDOW)

    if ($targetThread -ne 0) { [void][Dota2HelperWindow]::AttachThreadInput($currentThread, $targetThread, $false) }
    if ($foregroundThread -ne 0) { [void][Dota2HelperWindow]::AttachThreadInput($currentThread, $foregroundThread, $false) }
}

$focusSignalPath = Join-Path ([System.IO.Path]::GetTempPath()) 'Dota2Helper.focus'

$createdMutex = $false
$helperMutex = [System.Threading.Mutex]::new($true, 'Local\Dota2Helper.xphiyy.dota2helper', [ref]$createdMutex)
if (-not $createdMutex) {
    try { Set-Content -LiteralPath $focusSignalPath -Value ([DateTime]::UtcNow.Ticks) -Encoding ASCII } catch {}
    Focus-ExistingHelperWindow
    $helperMutex.Dispose()
    return
}

if ($PSScriptRoot) { $scriptDir = $PSScriptRoot } else { $scriptDir = (Get-Location).Path }
$projectRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$runnerDir = Join-Path $projectRoot 'src\runners'
$localDir = Join-Path $projectRoot 'local'
[void][System.IO.Directory]::CreateDirectory($localDir)
$workerScript = Join-Path $runnerDir 'Accept-DotaMatch.ps1'
$sequenceScript = Join-Path $runnerDir 'Invoke-DotaSequence.ps1'
$autoAcceptToolConfigPath = Join-Path $projectRoot 'config\tools\auto-accept.tool.json'
$createLobbyToolConfigPath = Join-Path $projectRoot 'config\tools\create-lobby.tool.json'
$dotaTargetConfigPath = Join-Path $projectRoot 'config\targets\dota-default.targets.json'
$configPath = Join-Path $localDir 'acceptor.config.json'
$machineCalibrationPath = Join-Path $localDir 'machine-calibration.json'
$gameModesPath = Join-Path $localDir 'game-modes.json'
$recorderToolsPath = Join-Path $localDir 'recorder-tools.json'
$runtimeLogPath = Join-Path $localDir 'acceptor.runtime.log'
$state = [ordered]@{
    Process = $null
    Closing = $false
    LogOffset = 0
    ApplyingMode = $false
    FocusSignal = ''
    ActiveFunction = ''
    CalibrationTool = ''
    CalibrationTargets = @()
    CalibrationIndex = 0
    CalibrationWasMouseDown = $false
    CalibrationIgnoreUntilUp = $false
    RecorderTool = ''
    RecorderOutputPath = ''
    RecorderTargets = @()
    RecorderIndex = 0
    RecorderClicks = @()
    RecorderWasMouseDown = $false
    RecorderIgnoreUntilUp = $false
    AutoAcceptSuppressUntilDotaLeaves = $false
    AutoAcceptStartedFromSignal = $false
    LastForegroundWasDota = $null
    LastForegroundProcessName = ''
    LastForegroundTransition = 'none'
    LastUserFocusLabel = 'mouse not checked'
    LastUserFocusIsOverDota = $false
    LastRecorderToolText = 'new-tool'
    SiriListener = $null
    SiriPort = 8765
    SiriLastMessage = 'Siri support off'
}

function Quote-Arg {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Join-Args {
    param([string[]]$Values)
    return (($Values | ForEach-Object { Quote-Arg $_ }) -join ' ')
}

function Get-SafeName {
    param([string]$Value)
    $safe = ($Value -replace '[^\w.-]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'default' }
    return $safe
}

function Get-CreateLobbyConfigPath {
    $gameMod = if ($cmbGameMode -and -not [string]::IsNullOrWhiteSpace($cmbGameMode.Text)) { $cmbGameMode.Text } else { 'DOTA2 IM' }
    $safeGameMod = Get-SafeName $gameMod
    return Join-Path $localDir "create-lobby.$safeGameMod.config.json"
}

function Get-ForegroundProcessName {
    $hwnd = [Dota2HelperWindow]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return '' }

    $foregroundPid = [uint32]0
    [void][Dota2HelperWindow]::GetWindowThreadProcessId($hwnd, [ref]$foregroundPid)
    if ($foregroundPid -eq 0) { return '' }

    try {
        return ([System.Diagnostics.Process]::GetProcessById([int]$foregroundPid)).ProcessName
    }
    catch {
        return ''
    }
}

function Test-DotaForegroundProcess {
    (Get-ForegroundProcessName) -ieq 'dota2'
}

function Get-DotaWindowHandle {
    $processes = @()
    try {
        $processes = @(Get-Process -Name 'dota2' -ErrorAction SilentlyContinue)
    }
    catch {
        return [IntPtr]::Zero
    }

    foreach ($process in $processes) {
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $process.MainWindowHandle
        }
    }

    return [IntPtr]::Zero
}

function Get-CursorWorkingAreaStatus {
    $point = New-Object Dota2HelperWindow+POINT
    if (-not [Dota2HelperWindow]::GetCursorPos([ref]$point)) {
        return [pscustomobject]@{
            Label = 'unknown'
            IsOverDota = $false
        }
    }

    $hwnd = Get-DotaWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) {
        return [pscustomobject]@{
            Label = "mouse at $($point.X),$($point.Y), Dota window not found"
            IsOverDota = $false
        }
    }

    $rect = New-Object Dota2HelperWindow+RECT
    if (-not [Dota2HelperWindow]::GetWindowRect($hwnd, [ref]$rect)) {
        return [pscustomobject]@{
            Label = "mouse at $($point.X),$($point.Y), Dota window bounds unknown"
            IsOverDota = $false
        }
    }

    $isOverDota = (
        $point.X -ge $rect.Left -and
        $point.X -lt $rect.Right -and
        $point.Y -ge $rect.Top -and
        $point.Y -lt $rect.Bottom
    )
    $areaLabel = if ($isOverDota) { 'over Dota' } else { 'outside Dota' }

    return [pscustomobject]@{
        Label = "mouse $areaLabel at $($point.X),$($point.Y)"
        IsOverDota = $isOverDota
    }
}

function Test-CursorOutsideDotaWorkingArea {
    -not [bool]$state.LastUserFocusIsOverDota
}

function Update-ForegroundStatus {
    param([string]$ProcessName)

    if ($null -eq $lblForeground -or $lblForeground.IsDisposed) { return }

    $processLabel = if ([string]::IsNullOrWhiteSpace($ProcessName)) { 'unknown' } else { $ProcessName }
    $transitionLabel = if ([string]::IsNullOrWhiteSpace($state.LastForegroundTransition)) { 'none' } else { $state.LastForegroundTransition }
    $lblForeground.Text = "Foreground: $processLabel, transition: $transitionLabel"
    if ($null -ne $lblUserFocus -and -not $lblUserFocus.IsDisposed) {
        $userFocusLabel = if ([string]::IsNullOrWhiteSpace($state.LastUserFocusLabel)) { 'mouse not checked' } else { $state.LastUserFocusLabel }
        $lblUserFocus.Text = "User focus: $userFocusLabel"
    }
}

function Get-SelectedGameMode {
    if ($cmbGameMode -and -not [string]::IsNullOrWhiteSpace($cmbGameMode.Text)) {
        return $cmbGameMode.Text.Trim()
    }
    return 'DOTA2 IM'
}

function Get-SavedGameModes {
    $fallback = @('DOTA2 IM')
    if (-not (Test-Path -LiteralPath $gameModesPath)) { return $fallback }

    try {
        $cfg = Get-Content -LiteralPath $gameModesPath -Raw | ConvertFrom-Json
        $modes = @($cfg.gameModes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        if ($modes.Count -eq 0) { return $fallback }
        return @($modes | Select-Object -Unique)
    }
    catch {
        return $fallback
    }
}

function Save-GameModes {
    param([string[]]$GameModes)

    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $gameModesPath))
    [pscustomobject]@{
        updatedAt = (Get-Date).ToString('o')
        gameModes = @($GameModes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $gameModesPath -Encoding UTF8
}

function Set-GameModeItems {
    param([string]$Selected)

    if ($null -eq $cmbGameMode) { return }
    $state.ApplyingMode = $true
    try {
        $modes = @(Get-SavedGameModes)
        $cmbGameMode.Items.Clear()
        foreach ($mode in $modes) {
            [void]$cmbGameMode.Items.Add($mode)
        }

        if ([string]::IsNullOrWhiteSpace($Selected)) { $Selected = $modes[0] }
        $cmbGameMode.Text = $Selected
    }
    finally {
        $state.ApplyingMode = $false
    }
}

function Save-SelectedGameMode {
    $mode = Get-SelectedGameMode
    $modes = @(Get-SavedGameModes)
    if ($modes -notcontains $mode) {
        $modes += $mode
    }

    Save-GameModes -GameModes $modes
    Set-GameModeItems -Selected $mode
    Add-Log "Saved Game mod: $mode"
    Update-ConfigurationText
}

function Get-SelectedRecorderTool {
    if ($cmbRecorderTool -and -not [string]::IsNullOrWhiteSpace($cmbRecorderTool.Text)) {
        return $cmbRecorderTool.Text.Trim()
    }
    return 'new-tool'
}

function Get-RecorderDefaultOutput {
    param([string]$Tool)

    if ([string]::IsNullOrWhiteSpace($Tool)) { $Tool = 'new-tool' }
    $safeTool = Get-SafeName $Tool
    return "local\$safeTool.config.json"
}

function Get-SavedRecorderTools {
    $fallback = @('new-tool')
    if (-not (Test-Path -LiteralPath $recorderToolsPath)) { return $fallback }

    try {
        $cfg = Get-Content -LiteralPath $recorderToolsPath -Raw | ConvertFrom-Json
        $tools = @($cfg.recorderTools | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        if ($tools.Count -eq 0) { return $fallback }
        return @($tools | Select-Object -Unique)
    }
    catch {
        return $fallback
    }
}

function Save-RecorderTools {
    param([string[]]$RecorderTools)

    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $recorderToolsPath))
    [pscustomobject]@{
        updatedAt = (Get-Date).ToString('o')
        recorderTools = @($RecorderTools | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $recorderToolsPath -Encoding UTF8
}

function Set-RecorderToolItems {
    param([string]$Selected)

    if ($null -eq $cmbRecorderTool) { return }
    $state.ApplyingMode = $true
    try {
        $tools = @(Get-SavedRecorderTools)
        $cmbRecorderTool.Items.Clear()
        foreach ($tool in $tools) {
            [void]$cmbRecorderTool.Items.Add($tool)
        }

        if ([string]::IsNullOrWhiteSpace($Selected)) { $Selected = $tools[0] }
        $cmbRecorderTool.Text = $Selected
        $state.LastRecorderToolText = $Selected
        if ($txtRecorderOutput) {
            $txtRecorderOutput.Text = Get-RecorderDefaultOutput -Tool $Selected
        }
    }
    finally {
        $state.ApplyingMode = $false
    }
}

function Save-SelectedRecorderTool {
    $tool = Get-SelectedRecorderTool
    $tools = @(Get-SavedRecorderTools)
    if ($tools -notcontains $tool) {
        $tools += $tool
    }

    Save-RecorderTools -RecorderTools $tools
    Set-RecorderToolItems -Selected $tool
    Add-Log "Saved recorder tool: $tool"
    Update-ConfigurationText
}

function Add-Log {
    param([string]$Message)
    if ($null -eq $txtLog -or $txtLog.IsDisposed) { return }
    if ($Message -match '^\[\d{2}:\d{2}:\d{2}\]\s') {
        $txtLog.AppendText("$Message`r`n")
    }
    else {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $txtLog.AppendText("[$timestamp] $Message`r`n")
    }
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Sync-WorkerLog {
    if (-not (Test-Path -LiteralPath $runtimeLogPath)) { return }

    try {
        $stream = [System.IO.File]::Open($runtimeLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($state.LogOffset -gt $stream.Length) { $state.LogOffset = 0 }
            [void]$stream.Seek([int64]$state.LogOffset, [System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $newText = $reader.ReadToEnd()
            $state.LogOffset = $stream.Position
            $reader.Dispose()
        }
        finally {
            $stream.Dispose()
        }

        if (-not [string]::IsNullOrWhiteSpace($newText)) {
            foreach ($line in ($newText -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Add-Log $line }
            }
        }
    }
    catch {
        # The worker may be appending at the same instant. The next timer tick will retry.
    }
}

function Get-CalibrationText {
    $module = if ($cmbModule -and $cmbModule.SelectedItem) { [string]$cmbModule.SelectedItem } else { 'Auto Accept' }

    if ($state.ActiveFunction -eq 'Calibration') {
        if (-not (Test-Path -LiteralPath $machineCalibrationPath)) { return 'Machine calibration: none' }
        try {
            $cfg = Get-Content -LiteralPath $machineCalibrationPath -Raw | ConvertFrom-Json
            return "Machine calibration: updated $($cfg.updatedAt)"
        }
        catch {
            return 'Machine calibration: unreadable'
        }
    }

    if ($module -eq 'Create Lobby') {
        $lobbyConfigPath = Get-CreateLobbyConfigPath
        if (-not (Test-Path -LiteralPath $lobbyConfigPath)) { return 'Sequence config: default template will be created on start' }
        try {
            $cfg = Get-Content -LiteralPath $lobbyConfigPath -Raw | ConvertFrom-Json
            $steps = if ($cfg.steps) { $cfg.steps } else { $cfg.Steps }
            $screenWidth = if ($cfg.screenWidth) { $cfg.screenWidth } else { $cfg.ScreenWidth }
            $screenHeight = if ($cfg.screenHeight) { $cfg.screenHeight } else { $cfg.ScreenHeight }
            return "Sequence config: $($steps.Count) steps for $screenWidth`x$screenHeight"
        }
        catch {
            return 'Sequence config: unreadable'
        }
    }

    if (-not (Test-Path -LiteralPath $configPath)) { return 'Calibration: none' }
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        return "Calibration: $($cfg.ClickX),$($cfg.ClickY) on $($cfg.ScreenWidth)x$($cfg.ScreenHeight)"
    }
    catch {
        return 'Calibration: unreadable config'
    }
}

function Set-RunningState {
    param([bool]$Running)
    if ($null -eq $btnStart -or $btnStart.IsDisposed) { return }
    $btnStart.Enabled = -not $Running
    $btnStop.Enabled = $Running
    $btnCalibrate.Enabled = -not $Running
    $cmbModule.Enabled = -not $Running
    $grpMode.Enabled = -not $Running
    $lblStatus.Text = if ($Running) { 'Run: running' } else { 'Run: stopped' }
}

function Stop-Worker {
    try {
        if ($null -ne $state.Process -and -not $state.Process.HasExited) {
            $state.Process.Kill()
            [void]$state.Process.WaitForExit(1500)
            Sync-WorkerLog
            if (-not $state.Closing) { Add-Log 'Stopped capture process.' }
        }
        if ($null -ne $state.Process) {
            $state.Process.Dispose()
        }
    }
    catch {
        if (-not $state.Closing) { Add-Log "Stop failed: $($_.Exception.Message)" }
    }
    finally {
        $state.Process = $null
        if (-not $state.Closing) { Set-RunningState $false }
    }
}

function Start-HiddenWorker {
    param([string[]]$WorkerArgs)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = Join-Args $WorkerArgs
    $psi.WorkingDirectory = $projectRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    return $proc
}

function Start-AutoAcceptWorker {
    param(
        [string]$Trigger = 'manual',
        [bool]$ForceAllowAnyForeground = $false
    )

    if ($null -ne $state.Process -and -not $state.Process.HasExited) {
        return $false
    }

    Set-Content -LiteralPath $runtimeLogPath -Value '' -Encoding UTF8
    $state.LogOffset = 0

    $argsList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $workerScript,
        '-PollMs', [string][int]$numPoll.Value,
        '-StableHits', [string][int]$numStable.Value,
        '-CooldownSeconds', [string][int]$numCooldown.Value,
        '-ToolConfigPath', $autoAcceptToolConfigPath,
        '-TargetConfigPath', $dotaTargetConfigPath,
        '-LogPath', $runtimeLogPath
    )

    if ($chkNoClick.Checked) { $argsList += '-NoClick' }
    if ($chkVerbose.Checked) { $argsList += '-VerboseDetection' }
    if ($chkAnyForeground.Checked -or $ForceAllowAnyForeground) { $argsList += '-AllowAnyForeground' }
    if ($chkStopAfter.Checked) { $argsList += '-StopAfterAccept' }

    $state.Process = Start-HiddenWorker -WorkerArgs $argsList
    $state.AutoAcceptStartedFromSignal = $Trigger -like 'dota2 foreground*'
    Set-RunningState $true
    Add-Log "Started Auto Accept from $Trigger, PID $($state.Process.Id)."
    return $true
}

function Start-CreateLobbyWorker {
    param([string]$Trigger = 'manual')

    if ($null -ne $state.Process -and -not $state.Process.HasExited) {
        return $false
    }

    Set-Content -LiteralPath $runtimeLogPath -Value '' -Encoding UTF8
    $state.LogOffset = 0
    $lobbyConfigPath = Get-CreateLobbyConfigPath
    $argsList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $sequenceScript,
        '-Tool', 'CreateLobby',
        '-ConfigPath', $lobbyConfigPath,
        '-ToolConfigPath', $createLobbyToolConfigPath,
        '-ModGameName', (Get-SelectedGameMode),
        '-StepDelayMs', [string][int]$numStepDelay.Value,
        '-LogPath', $runtimeLogPath
    )
    if ($chkLobbyDryRun.Checked) { $argsList += '-DryRun' }

    $state.Process = Start-HiddenWorker -WorkerArgs $argsList
    Set-RunningState $true
    Add-Log "Started Create Lobby from $Trigger, PID $($state.Process.Id)."
    return $true
}

function Get-NormalizedToolName {
    param([string]$Tool)

    $normalized = ($Tool -replace '[^a-zA-Z0-9]+', '').ToLowerInvariant()
    switch ($normalized) {
        { $_ -in @('autoaccept', 'autoacceptor', 'accept', 'acceptor', 'useautoacceptor') } { return 'Auto Accept' }
        { $_ -in @('createlobby', 'lobby', 'customlobby') } { return 'Create Lobby' }
        default { return '' }
    }
}

function Start-ToolFromCommand {
    param(
        [string]$Tool,
        [string]$Trigger = 'command'
    )

    if (-not [string]::IsNullOrWhiteSpace($state.ActiveFunction)) {
        return "Cannot start tool while $($state.ActiveFunction) is active."
    }
    if ($null -ne $state.Process -and -not $state.Process.HasExited) {
        return 'A tool is already running.'
    }

    $module = Get-NormalizedToolName -Tool $Tool
    if ([string]::IsNullOrWhiteSpace($module)) {
        return "Unknown tool '$Tool'. Supported: auto-accept, create-lobby."
    }

    $cmbModule.SelectedItem = $module
    Set-ActiveModule -Module $module

    if ($module -eq 'Auto Accept') {
        if (Start-AutoAcceptWorker -Trigger $Trigger) { return 'Started Auto Accept.' }
        return 'Auto Accept did not start.'
    }
    if ($module -eq 'Create Lobby') {
        if (Start-CreateLobbyWorker -Trigger $Trigger) { return 'Started Create Lobby.' }
        return 'Create Lobby did not start.'
    }

    return "Tool '$module' cannot be started from Siri."
}

function ConvertFrom-SiriQueryString {
    param([string]$Query)

    $values = @{}
    if ([string]::IsNullOrWhiteSpace($Query)) { return $values }
    $trimmed = $Query.TrimStart('?')
    foreach ($pair in ($trimmed -split '&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $parts = $pair -split '=', 2
        $key = [Uri]::UnescapeDataString($parts[0])
        $value = if ($parts.Count -gt 1) { [Uri]::UnescapeDataString(($parts[1] -replace '\+', ' ')) } else { '' }
        $values[$key] = $value
    }
    return $values
}

function ConvertFrom-SiriBody {
    param(
        [string]$Body,
        [string]$ContentType
    )

    $values = @{}
    if ([string]::IsNullOrWhiteSpace($Body)) { return $values }

    if ($ContentType -match 'application/json') {
        try {
            $json = $Body | ConvertFrom-Json
            foreach ($property in $json.PSObject.Properties) {
                $values[$property.Name] = [string]$property.Value
            }
            return $values
        }
        catch {
            return $values
        }
    }

    return ConvertFrom-SiriQueryString -Query $Body
}

function Merge-SiriValues {
    param(
        [hashtable]$Base,
        [hashtable]$Overrides
    )

    $merged = @{}
    foreach ($key in $Base.Keys) { $merged[$key] = $Base[$key] }
    foreach ($key in $Overrides.Keys) { $merged[$key] = $Overrides[$key] }
    return $merged
}

function Send-SiriHttpResponse {
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [int]$StatusCode,
        [string]$Body
    )

    $reason = if ($StatusCode -eq 200) { 'OK' } elseif ($StatusCode -eq 404) { 'Not Found' } else { 'Bad Request' }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $header = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $stream = $Client.GetStream()
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    $stream.Write($bodyBytes, 0, $bodyBytes.Length)
}

function Invoke-SiriHttpRequest {
    param([System.Net.Sockets.TcpClient]$Client)

    try {
        $Client.ReceiveTimeout = 1000
        $buffer = New-Object byte[] 8192
        $stream = $Client.GetStream()
        $count = $stream.Read($buffer, 0, $buffer.Length)
        if ($count -le 0) { return }

        $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count)
        $headerEnd = $request.IndexOf("`r`n`r`n")
        if ($headerEnd -lt 0) {
            Send-SiriHttpResponse -Client $Client -StatusCode 400 -Body 'Invalid HTTP request.'
            return
        }

        $headerText = $request.Substring(0, $headerEnd)
        $body = $request.Substring($headerEnd + 4)
        $headerLines = $headerText -split "`r?`n"
        $firstLine = $headerLines[0]
        if ($firstLine -notmatch '^(GET|POST)\s+(\S+)\s+HTTP/') {
            Send-SiriHttpResponse -Client $Client -StatusCode 400 -Body 'Only GET and POST requests are supported.'
            return
        }

        $method = $matches[1].ToUpperInvariant()
        $requestUri = [Uri]::new("http://localhost$($matches[2])")
        $headers = @{}
        foreach ($line in ($headerLines | Select-Object -Skip 1)) {
            $parts = $line -split ':', 2
            if ($parts.Count -eq 2) { $headers[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim() }
        }

        if ($method -eq 'POST' -and $headers.ContainsKey('content-length')) {
            $contentLength = [int]$headers['content-length']
            $bodyBytesAlreadyRead = [System.Text.Encoding]::ASCII.GetByteCount($body)
            while ($bodyBytesAlreadyRead -lt $contentLength) {
                $remainingBuffer = New-Object byte[] ([Math]::Min(4096, $contentLength - $bodyBytesAlreadyRead))
                $read = $stream.Read($remainingBuffer, 0, $remainingBuffer.Length)
                if ($read -le 0) { break }
                $body += [System.Text.Encoding]::UTF8.GetString($remainingBuffer, 0, $read)
                $bodyBytesAlreadyRead += $read
            }
        }

        $query = ConvertFrom-SiriQueryString -Query $requestUri.Query
        $contentType = if ($headers.ContainsKey('content-type')) { $headers['content-type'] } else { '' }
        $bodyValues = if ($method -eq 'POST') { ConvertFrom-SiriBody -Body $body -ContentType $contentType } else { @{} }
        $values = Merge-SiriValues -Base $query -Overrides $bodyValues
        $path = $requestUri.AbsolutePath.TrimEnd('/').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($path)) { $path = '/' }

        switch ($path) {
            '/start' {
                $tool = if ($values.ContainsKey('tool')) { $values['tool'] } else { 'auto-accept' }
                $message = Start-ToolFromCommand -Tool $tool -Trigger 'Siri'
                $state.SiriLastMessage = $message
                Add-Log "Siri command: $message"
                Send-SiriHttpResponse -Client $Client -StatusCode 200 -Body $message
            }
            '/create-lobby' {
                $message = Start-ToolFromCommand -Tool 'create-lobby' -Trigger 'Siri POST'
                $state.SiriLastMessage = $message
                Add-Log "Siri command: $message"
                Send-SiriHttpResponse -Client $Client -StatusCode 200 -Body $message
            }
            '/stop' {
                Stop-Worker
                $message = 'Stopped current tool.'
                $state.SiriLastMessage = $message
                Add-Log "Siri command: $message"
                Send-SiriHttpResponse -Client $Client -StatusCode 200 -Body $message
            }
            '/status' {
                $running = ($null -ne $state.Process -and -not $state.Process.HasExited)
                $module = if ($cmbModule.SelectedItem) { [string]$cmbModule.SelectedItem } else { 'unknown' }
                $message = "Tool=$module; Running=$running; ActiveFunction=$($state.ActiveFunction)"
                $state.SiriLastMessage = $message
                Send-SiriHttpResponse -Client $Client -StatusCode 200 -Body $message
            }
            default {
                Send-SiriHttpResponse -Client $Client -StatusCode 404 -Body 'Supported paths: /start?tool=auto-accept, /start?tool=create-lobby, /create-lobby, /stop, /status'
            }
        }
    }
    catch {
        try { Send-SiriHttpResponse -Client $Client -StatusCode 400 -Body $_.Exception.Message } catch {}
    }
    finally {
        $Client.Close()
    }
}

function Get-LanAddress {
    try {
        $routeOutput = @(route print -4 0.0.0.0 2>$null)
        foreach ($line in $routeOutput) {
            if ($line -match '^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d{1,3}(?:\.\d{1,3}){3})\s+(\d{1,3}(?:\.\d{1,3}){3})\s+\d+\s*$') {
                $candidate = $matches[2]
                if ($candidate -notmatch '^127\.' -and $candidate -notmatch '^169\.254\.' -and $candidate -notmatch '^172\.(1[6-9]|2\d|3[0-1])\.') {
                    return $candidate
                }
            }
        }
    }
    catch {}

    try {
        $addresses = @([System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).AddressList |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and -not [System.Net.IPAddress]::IsLoopback($_) } |
            ForEach-Object { [string]$_ })

        $preferred = @($addresses | Where-Object { $_ -match '^192\.168\.' -or $_ -match '^10\.' })
        if ($preferred.Count -gt 0) { return $preferred[0] }
        if ($addresses.Count -gt 0) { return $addresses[0] }
    }
    catch {}

    return '127.0.0.1'
}

function Update-SiriStatus {
    if ($null -eq $txtSiriStatus -or $txtSiriStatus.IsDisposed) { return }
    if ($null -ne $state.SiriListener) {
        $txtSiriStatus.Text = "http://$(Get-LanAddress):$($state.SiriPort)/start?tool=auto-accept"
    }
    else {
        $txtSiriStatus.Text = 'Siri: off'
    }
}

function Start-SiriSupport {
    if ($null -ne $state.SiriListener) { return }

    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, [int]$state.SiriPort)
        $listener.Start()
        $state.SiriListener = $listener
        $state.SiriLastMessage = "Siri support listening on port $($state.SiriPort)"
        Add-Log $state.SiriLastMessage
    }
    catch {
        $state.SiriListener = $null
        $chkSiriSupport.Checked = $false
        Add-Log "Siri support failed: $($_.Exception.Message)"
    }
    Update-SiriStatus
}

function Stop-SiriSupport {
    if ($null -eq $state.SiriListener) { return }
    try { $state.SiriListener.Stop() } catch {}
    $state.SiriListener = $null
    $state.SiriLastMessage = 'Siri support off'
    Add-Log $state.SiriLastMessage
    Update-SiriStatus
}

function Poll-SiriSupport {
    if ($null -eq $state.SiriListener) { return }
    try {
        while ($state.SiriListener.Pending()) {
            $client = $state.SiriListener.AcceptTcpClient()
            Invoke-SiriHttpRequest -Client $client
        }
    }
    catch {
        Add-Log "Siri support stopped: $($_.Exception.Message)"
        Stop-SiriSupport
        if ($chkSiriSupport) { $chkSiriSupport.Checked = $false }
    }
}

function Invoke-SelfFocus {
    if ($null -eq $form -or $form.IsDisposed) { return }

    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }

    $form.Show()
    $form.Activate()
    $form.TopMost = $true
    $form.TopMost = $false
    $form.BringToFront()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Dota 2 Helper'
$form.Size = [System.Drawing.Size]::new(620, 666)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$lblModule = New-Object System.Windows.Forms.Label
$lblModule.Location = [System.Drawing.Point]::new(16, 16)
$lblModule.Size = [System.Drawing.Size]::new(70, 22)
$lblModule.Text = 'Tool'
$form.Controls.Add($lblModule)

$cmbModule = New-Object System.Windows.Forms.ComboBox
$cmbModule.Location = [System.Drawing.Point]::new(92, 13)
$cmbModule.Size = [System.Drawing.Size]::new(220, 24)
$cmbModule.DropDownStyle = 'DropDownList'
[void]$cmbModule.Items.Add('Auto Accept')
[void]$cmbModule.Items.Add('Create Lobby')
[void]$cmbModule.Items.Add('Operation Recorder')
$cmbModule.SelectedIndex = 0
$form.Controls.Add($cmbModule)

$chkSiriSupport = New-Object System.Windows.Forms.CheckBox
$chkSiriSupport.Location = [System.Drawing.Point]::new(330, 13)
$chkSiriSupport.Size = [System.Drawing.Size]::new(96, 24)
$chkSiriSupport.Text = 'Siri support'
$chkSiriSupport.Checked = $false
$form.Controls.Add($chkSiriSupport)

$txtSiriStatus = New-Object System.Windows.Forms.TextBox
$txtSiriStatus.Location = [System.Drawing.Point]::new(430, 13)
$txtSiriStatus.Size = [System.Drawing.Size]::new(104, 24)
$txtSiriStatus.ReadOnly = $true
$txtSiriStatus.Text = 'Siri: off'
$form.Controls.Add($txtSiriStatus)

$btnCopySiriUrl = New-Object System.Windows.Forms.Button
$btnCopySiriUrl.Location = [System.Drawing.Point]::new(540, 12)
$btnCopySiriUrl.Size = [System.Drawing.Size]::new(46, 26)
$btnCopySiriUrl.Text = 'Copy'
$form.Controls.Add($btnCopySiriUrl)

$grpStatus = New-Object System.Windows.Forms.GroupBox
$grpStatus.Location = [System.Drawing.Point]::new(16, 50)
$grpStatus.Size = [System.Drawing.Size]::new(570, 144)
$grpStatus.Text = 'Status'
$form.Controls.Add($grpStatus)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = [System.Drawing.Point]::new(18, 26)
$lblStatus.Size = [System.Drawing.Size]::new(170, 22)
$lblStatus.Text = 'Run: stopped'
$grpStatus.Controls.Add($lblStatus)

$lblCalibration = New-Object System.Windows.Forms.Label
$lblCalibration.Location = [System.Drawing.Point]::new(18, 54)
$lblCalibration.Size = [System.Drawing.Size]::new(530, 22)
$lblCalibration.Text = Get-CalibrationText
$grpStatus.Controls.Add($lblCalibration)

$lblForeground = New-Object System.Windows.Forms.Label
$lblForeground.Location = [System.Drawing.Point]::new(18, 82)
$lblForeground.Size = [System.Drawing.Size]::new(530, 22)
$lblForeground.Text = 'Foreground transition: none'
$grpStatus.Controls.Add($lblForeground)

$lblUserFocus = New-Object System.Windows.Forms.Label
$lblUserFocus.Location = [System.Drawing.Point]::new(18, 110)
$lblUserFocus.Size = [System.Drawing.Size]::new(530, 22)
$lblUserFocus.Text = 'User focus: mouse not checked'
$grpStatus.Controls.Add($lblUserFocus)

$lblConfiguration = New-Object System.Windows.Forms.Label
$lblConfiguration.Location = [System.Drawing.Point]::new(206, 26)
$lblConfiguration.Size = [System.Drawing.Size]::new(342, 22)
$lblConfiguration.Text = 'Config: Ready: click once'
$grpStatus.Controls.Add($lblConfiguration)

$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Location = [System.Drawing.Point]::new(16, 206)
$grpMode.Size = [System.Drawing.Size]::new(570, 170)
$grpMode.Text = 'Mode'
$form.Controls.Add($grpMode)

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Location = [System.Drawing.Point]::new(18, 30)
$lblMode.Size = [System.Drawing.Size]::new(70, 22)
$lblMode.Text = 'Mode'
$grpMode.Controls.Add($lblMode)

$cmbAcceptMode = New-Object System.Windows.Forms.ComboBox
$cmbAcceptMode.Location = [System.Drawing.Point]::new(92, 27)
$cmbAcceptMode.Size = [System.Drawing.Size]::new(190, 24)
$cmbAcceptMode.DropDownStyle = 'DropDownList'
[void]$cmbAcceptMode.Items.Add('Ready: click once')
[void]$cmbAcceptMode.Items.Add('Test: detect only')
[void]$cmbAcceptMode.Items.Add('Fast: lower delay')
[void]$cmbAcceptMode.Items.Add('Custom')
$cmbAcceptMode.SelectedIndex = 0
$grpMode.Controls.Add($cmbAcceptMode)

$lblModeHint = New-Object System.Windows.Forms.Label
$lblModeHint.Location = [System.Drawing.Point]::new(302, 28)
$lblModeHint.Size = [System.Drawing.Size]::new(244, 42)
$lblModeHint.Text = 'Clicks once, then exits after the button disappears.'
$grpMode.Controls.Add($lblModeHint)

$pnlAutoMode = New-Object System.Windows.Forms.Panel
$pnlAutoMode.Location = [System.Drawing.Point]::new(0, 0)
$pnlAutoMode.Size = [System.Drawing.Size]::new(570, 170)
$grpMode.Controls.Add($pnlAutoMode)

$pnlLobbyMode = New-Object System.Windows.Forms.Panel
$pnlLobbyMode.Location = [System.Drawing.Point]::new(0, 0)
$pnlLobbyMode.Size = [System.Drawing.Size]::new(570, 170)
$pnlLobbyMode.Visible = $false
$grpMode.Controls.Add($pnlLobbyMode)

$pnlRecorderMode = New-Object System.Windows.Forms.Panel
$pnlRecorderMode.Location = [System.Drawing.Point]::new(0, 0)
$pnlRecorderMode.Size = [System.Drawing.Size]::new(570, 170)
$pnlRecorderMode.Visible = $false
$grpMode.Controls.Add($pnlRecorderMode)

$lblMode.Parent = $pnlAutoMode
$cmbAcceptMode.Parent = $pnlAutoMode
$lblModeHint.Parent = $pnlAutoMode

$pnlCustomOptions = New-Object System.Windows.Forms.Panel
$pnlCustomOptions.Location = [System.Drawing.Point]::new(14, 70)
$pnlCustomOptions.Size = [System.Drawing.Size]::new(540, 86)
$pnlCustomOptions.Visible = $false
$pnlAutoMode.Controls.Add($pnlCustomOptions)

$chkNoClick = New-Object System.Windows.Forms.CheckBox
$chkNoClick.Location = [System.Drawing.Point]::new(4, 4)
$chkNoClick.Size = [System.Drawing.Size]::new(116, 24)
$chkNoClick.Text = 'Detect only'
$pnlCustomOptions.Controls.Add($chkNoClick)

$chkVerbose = New-Object System.Windows.Forms.CheckBox
$chkVerbose.Location = [System.Drawing.Point]::new(128, 4)
$chkVerbose.Size = [System.Drawing.Size]::new(110, 24)
$chkVerbose.Text = 'Verbose log'
$pnlCustomOptions.Controls.Add($chkVerbose)

$chkAnyForeground = New-Object System.Windows.Forms.CheckBox
$chkAnyForeground.Location = [System.Drawing.Point]::new(246, 4)
$chkAnyForeground.Size = [System.Drawing.Size]::new(158, 24)
$chkAnyForeground.Text = 'Allow any foreground'
$pnlCustomOptions.Controls.Add($chkAnyForeground)

$chkStopAfter = New-Object System.Windows.Forms.CheckBox
$chkStopAfter.Location = [System.Drawing.Point]::new(4, 32)
$chkStopAfter.Size = [System.Drawing.Size]::new(180, 24)
$chkStopAfter.Text = 'Stop after one accept'
$chkStopAfter.Checked = $true
$pnlCustomOptions.Controls.Add($chkStopAfter)

$chkStartOnDotaForeground = New-Object System.Windows.Forms.CheckBox
$chkStartOnDotaForeground.Location = [System.Drawing.Point]::new(92, 52)
$chkStartOnDotaForeground.Size = [System.Drawing.Size]::new(220, 24)
$chkStartOnDotaForeground.Text = 'Start when Dota foregrounds'
$chkStartOnDotaForeground.Checked = $true
$pnlAutoMode.Controls.Add($chkStartOnDotaForeground)

$lblPoll = New-Object System.Windows.Forms.Label
$lblPoll.Location = [System.Drawing.Point]::new(4, 62)
$lblPoll.Size = [System.Drawing.Size]::new(54, 22)
$lblPoll.Text = 'Poll ms'
$pnlCustomOptions.Controls.Add($lblPoll)

$numPoll = New-Object System.Windows.Forms.NumericUpDown
$numPoll.Location = [System.Drawing.Point]::new(62, 60)
$numPoll.Size = [System.Drawing.Size]::new(80, 24)
$numPoll.Minimum = 100
$numPoll.Maximum = 3000
$numPoll.Increment = 50
$numPoll.Value = 450
$pnlCustomOptions.Controls.Add($numPoll)

$lblStable = New-Object System.Windows.Forms.Label
$lblStable.Location = [System.Drawing.Point]::new(164, 62)
$lblStable.Size = [System.Drawing.Size]::new(66, 22)
$lblStable.Text = 'Stable hits'
$pnlCustomOptions.Controls.Add($lblStable)

$numStable = New-Object System.Windows.Forms.NumericUpDown
$numStable.Location = [System.Drawing.Point]::new(236, 60)
$numStable.Size = [System.Drawing.Size]::new(80, 24)
$numStable.Minimum = 1
$numStable.Maximum = 10
$numStable.Value = 3
$pnlCustomOptions.Controls.Add($numStable)

$lblCooldown = New-Object System.Windows.Forms.Label
$lblCooldown.Location = [System.Drawing.Point]::new(338, 62)
$lblCooldown.Size = [System.Drawing.Size]::new(76, 22)
$lblCooldown.Text = 'Cooldown s'
$pnlCustomOptions.Controls.Add($lblCooldown)

$numCooldown = New-Object System.Windows.Forms.NumericUpDown
$numCooldown.Location = [System.Drawing.Point]::new(420, 60)
$numCooldown.Size = [System.Drawing.Size]::new(80, 24)
$numCooldown.Minimum = 1
$numCooldown.Maximum = 120
$numCooldown.Value = 15
$pnlCustomOptions.Controls.Add($numCooldown)

$lblLobbyMode = New-Object System.Windows.Forms.Label
$lblLobbyMode.Location = [System.Drawing.Point]::new(18, 30)
$lblLobbyMode.Size = [System.Drawing.Size]::new(70, 22)
$lblLobbyMode.Text = 'Mode'
$pnlLobbyMode.Controls.Add($lblLobbyMode)

$cmbLobbyMode = New-Object System.Windows.Forms.ComboBox
$cmbLobbyMode.Location = [System.Drawing.Point]::new(92, 27)
$cmbLobbyMode.Size = [System.Drawing.Size]::new(190, 24)
$cmbLobbyMode.DropDownStyle = 'DropDownList'
[void]$cmbLobbyMode.Items.Add('Run sequence')
[void]$cmbLobbyMode.Items.Add('Dry run')
[void]$cmbLobbyMode.Items.Add('Custom')
$cmbLobbyMode.SelectedIndex = 0
$pnlLobbyMode.Controls.Add($cmbLobbyMode)

$lblLobbyHint = New-Object System.Windows.Forms.Label
$lblLobbyHint.Location = [System.Drawing.Point]::new(302, 28)
$lblLobbyHint.Size = [System.Drawing.Size]::new(244, 42)
$lblLobbyHint.Text = 'Creates or uses the local sequence config, then runs it.'
$pnlLobbyMode.Controls.Add($lblLobbyHint)

$lblModGame = New-Object System.Windows.Forms.Label
$lblModGame.Location = [System.Drawing.Point]::new(18, 74)
$lblModGame.Size = [System.Drawing.Size]::new(90, 22)
$lblModGame.Text = 'Game mod'
$pnlLobbyMode.Controls.Add($lblModGame)

$cmbGameMode = New-Object System.Windows.Forms.ComboBox
$cmbGameMode.Location = [System.Drawing.Point]::new(112, 72)
$cmbGameMode.Size = [System.Drawing.Size]::new(210, 24)
$cmbGameMode.DropDownStyle = 'DropDown'
$pnlLobbyMode.Controls.Add($cmbGameMode)

$btnSaveGameMode = New-Object System.Windows.Forms.Button
$btnSaveGameMode.Location = [System.Drawing.Point]::new(330, 71)
$btnSaveGameMode.Size = [System.Drawing.Size]::new(48, 26)
$btnSaveGameMode.Text = 'Save'
$pnlLobbyMode.Controls.Add($btnSaveGameMode)

$chkLobbyDryRun = New-Object System.Windows.Forms.CheckBox
$chkLobbyDryRun.Location = [System.Drawing.Point]::new(392, 72)
$chkLobbyDryRun.Size = [System.Drawing.Size]::new(110, 24)
$chkLobbyDryRun.Text = 'Dry run'
$pnlLobbyMode.Controls.Add($chkLobbyDryRun)

$lblStepDelay = New-Object System.Windows.Forms.Label
$lblStepDelay.Location = [System.Drawing.Point]::new(18, 112)
$lblStepDelay.Size = [System.Drawing.Size]::new(90, 22)
$lblStepDelay.Text = 'Step delay ms'
$pnlLobbyMode.Controls.Add($lblStepDelay)

$numStepDelay = New-Object System.Windows.Forms.NumericUpDown
$numStepDelay.Location = [System.Drawing.Point]::new(112, 110)
$numStepDelay.Size = [System.Drawing.Size]::new(90, 24)
$numStepDelay.Minimum = 50
$numStepDelay.Maximum = 5000
$numStepDelay.Increment = 50
$numStepDelay.Value = 200
$pnlLobbyMode.Controls.Add($numStepDelay)

$lblLobbyConfig = New-Object System.Windows.Forms.Label
$lblLobbyConfig.Location = [System.Drawing.Point]::new(224, 113)
$lblLobbyConfig.Size = [System.Drawing.Size]::new(322, 22)
$lblLobbyConfig.Text = 'Config: create-lobby.dota2-im.config.json'
$pnlLobbyMode.Controls.Add($lblLobbyConfig)

$lblRecorderTool = New-Object System.Windows.Forms.Label
$lblRecorderTool.Location = [System.Drawing.Point]::new(18, 30)
$lblRecorderTool.Size = [System.Drawing.Size]::new(90, 22)
$lblRecorderTool.Text = 'Tool name'
$pnlRecorderMode.Controls.Add($lblRecorderTool)

$cmbRecorderTool = New-Object System.Windows.Forms.ComboBox
$cmbRecorderTool.Location = [System.Drawing.Point]::new(112, 27)
$cmbRecorderTool.Size = [System.Drawing.Size]::new(190, 24)
$cmbRecorderTool.DropDownStyle = 'DropDown'
$pnlRecorderMode.Controls.Add($cmbRecorderTool)

$btnSaveRecorderTool = New-Object System.Windows.Forms.Button
$btnSaveRecorderTool.Location = [System.Drawing.Point]::new(310, 26)
$btnSaveRecorderTool.Size = [System.Drawing.Size]::new(48, 26)
$btnSaveRecorderTool.Text = 'Save'
$pnlRecorderMode.Controls.Add($btnSaveRecorderTool)

$lblRecorderHint = New-Object System.Windows.Forms.Label
$lblRecorderHint.Location = [System.Drawing.Point]::new(374, 28)
$lblRecorderHint.Size = [System.Drawing.Size]::new(172, 44)
$lblRecorderHint.Text = 'Guided click recorder. Follow the log prompts, then click Dota positions.'
$pnlRecorderMode.Controls.Add($lblRecorderHint)

$lblRecorderOutput = New-Object System.Windows.Forms.Label
$lblRecorderOutput.Location = [System.Drawing.Point]::new(18, 76)
$lblRecorderOutput.Size = [System.Drawing.Size]::new(90, 22)
$lblRecorderOutput.Text = 'Output'
$pnlRecorderMode.Controls.Add($lblRecorderOutput)

$txtRecorderOutput = New-Object System.Windows.Forms.TextBox
$txtRecorderOutput.Location = [System.Drawing.Point]::new(112, 74)
$txtRecorderOutput.Size = [System.Drawing.Size]::new(360, 24)
$txtRecorderOutput.Text = 'local\new-tool.config.json'
$pnlRecorderMode.Controls.Add($txtRecorderOutput)

$lblRecorderNote = New-Object System.Windows.Forms.Label
$lblRecorderNote.Location = [System.Drawing.Point]::new(112, 112)
$lblRecorderNote.Size = [System.Drawing.Size]::new(360, 34)
$lblRecorderNote.Text = 'For now it records click operations only and writes runnable JSON.'
$pnlRecorderMode.Controls.Add($lblRecorderNote)

$grpActions = New-Object System.Windows.Forms.GroupBox
$grpActions.Location = [System.Drawing.Point]::new(16, 388)
$grpActions.Size = [System.Drawing.Size]::new(570, 72)
$grpActions.Text = 'Buttons'
$form.Controls.Add($grpActions)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Location = [System.Drawing.Point]::new(18, 25)
$btnStart.Size = [System.Drawing.Size]::new(118, 32)
$btnStart.Text = 'Start'
$grpActions.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = [System.Drawing.Point]::new(146, 25)
$btnStop.Size = [System.Drawing.Size]::new(118, 32)
$btnStop.Text = 'Stop'
$btnStop.Enabled = $false
$grpActions.Controls.Add($btnStop)

$btnCalibrate = New-Object System.Windows.Forms.Button
$btnCalibrate.Location = [System.Drawing.Point]::new(274, 25)
$btnCalibrate.Size = [System.Drawing.Size]::new(118, 32)
$btnCalibrate.Text = 'Calibrate'
$grpActions.Controls.Add($btnCalibrate)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Location = [System.Drawing.Point]::new(402, 25)
$btnOpenFolder.Size = [System.Drawing.Size]::new(118, 32)
$btnOpenFolder.Text = 'Open folder'
$grpActions.Controls.Add($btnOpenFolder)

$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Location = [System.Drawing.Point]::new(16, 472)
$grpLog.Size = [System.Drawing.Size]::new(570, 128)
$grpLog.Text = 'Log'
$form.Controls.Add($grpLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = [System.Drawing.Point]::new(14, 22)
$txtLog.Size = [System.Drawing.Size]::new(540, 90)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$grpLog.Controls.Add($txtLog)

function Update-ConfigurationText {
    $module = if ($cmbModule.SelectedItem) { [string]$cmbModule.SelectedItem } else { 'Auto Accept' }

    if ($state.ActiveFunction -eq 'Calibration') {
        $target = if ($state.CalibrationIndex -lt $state.CalibrationTargets.Count) { [string]$state.CalibrationTargets[$state.CalibrationIndex] } else { 'done' }
        $lblConfiguration.Text = "Config: calibrate $($state.CalibrationTool), next $target"
        return
    }

    if ($module -eq 'Create Lobby') {
        $mode = if ($cmbLobbyMode.SelectedItem) { [string]$cmbLobbyMode.SelectedItem } else { 'Run sequence' }
        $dryRun = if ($chkLobbyDryRun.Checked) { ', dry run' } else { '' }
        $lblLobbyConfig.Text = "Config: $(Split-Path -Leaf (Get-CreateLobbyConfigPath))"
        $lblConfiguration.Text = "Config: $mode, $(Get-SelectedGameMode), delay $([int]$numStepDelay.Value)ms$dryRun"
        return
    }

    if ($module -eq 'Operation Recorder') {
        if ($state.ActiveFunction -eq 'OperationRecorder') {
            $next = $state.RecorderIndex + 1
            $lblConfiguration.Text = "Config: recording $($state.RecorderTool), next click $next"
        }
        else {
            $lblConfiguration.Text = "Config: record $(Get-SelectedRecorderTool) to $($txtRecorderOutput.Text)"
        }
        return
    }

    $mode = [string]$cmbAcceptMode.SelectedItem
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'Ready: click once' }

    if ($mode -eq 'Custom') {
        $flags = @()
        if ($chkNoClick.Checked) { $flags += 'detect only' }
        if ($chkVerbose.Checked) { $flags += 'verbose' }
        if ($chkAnyForeground.Checked) { $flags += 'any foreground' }
        if ($chkStartOnDotaForeground.Checked) { $flags += 'foreground signal' }
        if ($chkStopAfter.Checked) { $flags += 'stop after accept' }
        if ($flags.Count -eq 0) { $flags += 'click mode' }
        $lblConfiguration.Text = "Config: Custom, poll $([int]$numPoll.Value)ms, hits $([int]$numStable.Value), cooldown $([int]$numCooldown.Value)s, $($flags -join ', ')"
    }
    else {
        $lblConfiguration.Text = "Config: $mode"
    }
}

function Set-CustomOptionsVisible {
    param([bool]$Visible)
    $pnlCustomOptions.Visible = $Visible
    $chkStartOnDotaForeground.Visible = $Visible
}

function Get-CalibrationKey {
    param([string]$Value)
    ($Value -replace '[^\w]+', '_').Trim('_').ToLowerInvariant()
}

function Get-MachineCalibration {
    if (Test-Path -LiteralPath $machineCalibrationPath) {
        try {
            return Get-Content -LiteralPath $machineCalibrationPath -Raw | ConvertFrom-Json
        }
        catch {
            Add-Log "Machine calibration is unreadable; creating a new file."
        }
    }

    [pscustomobject]@{
        updatedAt = ''
        screenWidth = 0
        screenHeight = 0
        tools = [pscustomobject]@{}
    }
}

function Set-MachineCalibrationPoint {
    param(
        [string]$Tool,
        [string]$Target,
        [int]$X,
        [int]$Y
    )

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $cfg = Get-MachineCalibration
    $toolKey = Get-CalibrationKey $Tool
    $targetKey = Get-CalibrationKey $Target
    $root = [ordered]@{}

    foreach ($property in $cfg.PSObject.Properties) {
        $root[$property.Name] = $property.Value
    }

    $root.updatedAt = (Get-Date).ToString('o')
    $root.screenWidth = $screen.Width
    $root.screenHeight = $screen.Height

    $tools = [ordered]@{}
    if ($null -ne $cfg.tools) {
        foreach ($property in $cfg.tools.PSObject.Properties) {
            $tools[$property.Name] = $property.Value
        }
    }

    $targets = [ordered]@{}
    if ($tools.Contains($toolKey) -and $null -ne $tools[$toolKey]) {
        foreach ($property in $tools[$toolKey].PSObject.Properties) {
            $targets[$property.Name] = $property.Value
        }
    }

    $targets[$targetKey] = [ordered]@{
        label = $Target
        x = $X
        y = $Y
        screenWidth = $screen.Width
        screenHeight = $screen.Height
        updatedAt = (Get-Date).ToString('o')
    }
    $tools[$toolKey] = [pscustomobject]$targets
    $root.tools = [pscustomobject]$tools

    [pscustomobject]$root | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $machineCalibrationPath -Encoding UTF8

    if ($Tool -eq 'Auto Accept' -and $Target -eq 'Accept button') {
        $autoAcceptConfig = [ordered]@{
            ClickX = $X
            ClickY = $Y
            ScreenWidth = $screen.Width
            ScreenHeight = $screen.Height
            CreatedAt = (Get-Date).ToString('o')
            Source = 'machine-calibration'
        }
        $autoAcceptConfig | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    }
}

function Get-CalibrationTargetsForTool {
    param([string]$Tool)

    if ($Tool -eq 'Create Lobby') {
        $gameMod = Get-SelectedGameMode
        return @(
            'ARCADE',
            'LOBBY LIST',
            'CREATE CUSTOM LOBBY',
            'GAME MOD DROPDOWN',
            "GAME MOD VALUE: $gameMod",
            'SERVER LOCATION DROPDOWN',
            'SERVER LOCATION VALUE',
            'CREATE'
        )
    }

    return @('Accept button')
}

function Get-ResolvedRecorderOutputPath {
    $outputPath = $txtRecorderOutput.Text
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        $outputPath = 'local\new-tool.config.json'
    }
    if (-not [System.IO.Path]::IsPathRooted($outputPath)) {
        $outputPath = Join-Path $projectRoot $outputPath
    }
    return $outputPath
}

function New-ClickStep {
    param(
        [string]$Target,
        [int]$X,
        [int]$Y
    )

    [ordered]@{
        name = "Click $Target"
        action = 'click'
        target = $Target
        x = $X
        y = $Y
    }
}

function Get-RecorderToolName {
    $tool = (Get-SelectedRecorderTool).Trim()
    if ([string]::IsNullOrWhiteSpace($tool)) { return 'new-tool' }
    return $tool
}

function Convert-ClicksToRecordedConfig {
    param([object[]]$Clicks)

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $index = 0
    [ordered]@{
        tool = $state.RecorderTool
        source = 'operation-recorder'
        screenWidth = $screen.Width
        screenHeight = $screen.Height
        notes = 'Generated by the GUI Operation Recorder. Undefined tool, click operations only.'
        steps = @($Clicks | ForEach-Object {
            $index++
            [ordered]@{
                name = "Click $index"
                action = 'click'
                target = "click_$index"
                x = [int]$_.x
                y = [int]$_.y
            }
        })
    }
}

function Save-RecordedSequence {
    if (@($state.RecorderClicks).Count -eq 0) {
        throw 'No clicks were recorded.'
    }

    $outputPath = $state.RecorderOutputPath
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath))
    $config = Convert-ClicksToRecordedConfig -Clicks @($state.RecorderClicks)
    [pscustomobject]$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8
    Add-Log "Recorder wrote runnable JSON: $outputPath"
}

function Reset-OperationRecorderState {
    $state.ActiveFunction = ''
    $state.RecorderTool = ''
    $state.RecorderOutputPath = ''
    $state.RecorderTargets = @()
    $state.RecorderIndex = 0
    $state.RecorderClicks = @()
    $state.RecorderWasMouseDown = $false
    $state.RecorderIgnoreUntilUp = $false
    Set-ActiveModule -Module ([string]$cmbModule.SelectedItem)
}

function Write-RecorderPrompt {
    if ($state.ActiveFunction -ne 'OperationRecorder') { return }

    $stepNumber = $state.RecorderIndex + 1
    Add-Log "Record click $stepNumber for '$($state.RecorderTool)'. Click Finish to save, or Stop to cancel."
    Update-ConfigurationText
}

function Start-OperationRecorder {
    $tool = Get-RecorderToolName

    $state.ActiveFunction = 'OperationRecorder'
    $state.RecorderTool = $tool
    $state.RecorderOutputPath = Get-ResolvedRecorderOutputPath
    $state.RecorderTargets = @()
    $state.RecorderIndex = 0
    $state.RecorderClicks = @()
    $state.RecorderWasMouseDown = $false
    $state.RecorderIgnoreUntilUp = $true

    Set-ActiveModule -Module ([string]$cmbModule.SelectedItem)
    Add-Log "Operation recorder started for $tool. It will write click-only JSON to $($state.RecorderOutputPath)."
    Write-RecorderPrompt
}

function Finish-OperationRecorder {
    if ($state.ActiveFunction -ne 'OperationRecorder') { return }
    Save-RecordedSequence
    Add-Log "Operation recording complete for $($state.RecorderTool)."
    Reset-OperationRecorderState
}

function Stop-OperationRecorder {
    if ($state.ActiveFunction -ne 'OperationRecorder') { return }
    $tool = $state.RecorderTool
    Reset-OperationRecorderState
    Add-Log "Operation recording cancelled for $tool."
}

function Record-OperationClick {
    if ($state.ActiveFunction -ne 'OperationRecorder') { return }

    $position = [System.Windows.Forms.Cursor]::Position
    $step = [ordered]@{
        x = $position.X
        y = $position.Y
    }
    $state.RecorderClicks = @($state.RecorderClicks) + @([pscustomobject]$step)
    $state.RecorderIndex++
    Add-Log "Recorded click $($state.RecorderIndex) at $($position.X),$($position.Y)."
    Write-RecorderPrompt
}

function Write-CalibrationPrompt {
    if ($state.ActiveFunction -ne 'Calibration') { return }

    if ($state.CalibrationIndex -ge $state.CalibrationTargets.Count) {
        Add-Log "Calibration complete for $($state.CalibrationTool). Saved to local\machine-calibration.json."
        if ($state.CalibrationTool -eq 'Create Lobby') {
            Add-Log 'Create Lobby sequence will refresh from calibration on the next run or dry run.'
        }
        $state.ActiveFunction = ''
        $state.CalibrationTool = ''
        $state.CalibrationTargets = @()
        $state.CalibrationIndex = 0
        Set-ActiveModule -Module ([string]$cmbModule.SelectedItem)
        return
    }

    $stepNumber = $state.CalibrationIndex + 1
    $target = [string]$state.CalibrationTargets[$state.CalibrationIndex]
    Add-Log "Calibration $stepNumber/$($state.CalibrationTargets.Count): click the center of '$target' in Dota."
    Update-ConfigurationText
}

function Start-CalibrationRecorder {
    param([string]$Tool)

    $state.ActiveFunction = 'Calibration'
    $state.CalibrationTool = $Tool
    $state.CalibrationTargets = @(Get-CalibrationTargetsForTool -Tool $Tool)
    $state.CalibrationIndex = 0
    $state.CalibrationWasMouseDown = $false
    $state.CalibrationIgnoreUntilUp = $true

    Set-ActiveModule -Module ([string]$cmbModule.SelectedItem)
    Add-Log "Calibration started for $Tool. Follow the log prompts; each left click records the next position."
    Write-CalibrationPrompt
}

function Stop-CalibrationRecorder {
    if ($state.ActiveFunction -ne 'Calibration') { return }
    $tool = $state.CalibrationTool
    $state.ActiveFunction = ''
    $state.CalibrationTool = ''
    $state.CalibrationTargets = @()
    $state.CalibrationIndex = 0
    $state.CalibrationWasMouseDown = $false
    $state.CalibrationIgnoreUntilUp = $false
    Set-ActiveModule -Module ([string]$cmbModule.SelectedItem)
    Add-Log "Calibration cancelled for $tool."
}

function Record-CalibrationClick {
    if ($state.ActiveFunction -ne 'Calibration') { return }
    if ($state.CalibrationIndex -ge $state.CalibrationTargets.Count) { return }

    $position = [System.Windows.Forms.Cursor]::Position
    $target = [string]$state.CalibrationTargets[$state.CalibrationIndex]
    Set-MachineCalibrationPoint -Tool $state.CalibrationTool -Target $target -X $position.X -Y $position.Y
    Add-Log "Saved $($state.CalibrationTool) / $target at $($position.X),$($position.Y)."

    $state.CalibrationIndex++
    $lblCalibration.Text = Get-CalibrationText
    Write-CalibrationPrompt
}

function Set-LobbyMode {
    param([string]$Mode)

    $state.ApplyingMode = $true
    try {
        switch ($Mode) {
            'Run sequence' {
                $chkLobbyDryRun.Checked = $false
                $numStepDelay.Value = 200
                $lblLobbyHint.Text = 'Creates or uses the local sequence config, then runs it.'
            }
            'Dry run' {
                $chkLobbyDryRun.Checked = $true
                $numStepDelay.Value = 200
                $lblLobbyHint.Text = 'Logs each configured step without clicking or typing.'
            }
            default {
                $lblLobbyHint.Text = 'Use the configured values exactly.'
            }
        }
    }
    finally {
        $state.ApplyingMode = $false
        Update-ConfigurationText
    }
}

function Set-ActiveModule {
    param([string]$Module)

    $isLobby = $Module -eq 'Create Lobby'
    $isRecorder = $Module -eq 'Operation Recorder'
    $pnlAutoMode.Visible = -not $isLobby -and -not $isRecorder
    $pnlLobbyMode.Visible = $isLobby
    $pnlRecorderMode.Visible = $isRecorder
    if ($isRecorder) {
        $pnlRecorderMode.BringToFront()
        $grpMode.Text = 'Mode'
        $btnStart.Text = 'Record'
        $btnCalibrate.Text = 'Open output'
    }
    elseif ($isLobby) {
        $pnlLobbyMode.BringToFront()
        $grpMode.Text = 'Mode'
        $btnStart.Text = 'Run'
        $btnCalibrate.Text = 'Calibrate'
    }
    else {
        $pnlAutoMode.BringToFront()
        $grpMode.Text = 'Mode'
        $btnStart.Text = 'Start'
        $btnCalibrate.Text = 'Calibrate'
    }

    if ($state.ActiveFunction -eq 'Calibration') {
        $btnStart.Enabled = $false
        $btnStop.Enabled = $false
        $btnCalibrate.Text = 'Cancel'
        $cmbModule.Enabled = $false
    }
    elseif ($state.ActiveFunction -eq 'OperationRecorder') {
        $btnStart.Text = 'Finish'
        $btnStop.Enabled = $true
        $btnCalibrate.Enabled = $false
        $cmbModule.Enabled = $false
    }
    else {
        $btnStart.Enabled = $true
        if ($null -eq $state.Process -or $state.Process.HasExited) { $btnStop.Enabled = $false }
        $btnCalibrate.Enabled = $true
        $cmbModule.Enabled = $true
    }

    $lblCalibration.Text = Get-CalibrationText
    Update-ConfigurationText
}

function Set-AcceptMode {
    param([string]$Mode)

    $state.ApplyingMode = $true
    try {
        switch ($Mode) {
            'Ready: click once' {
                $chkNoClick.Checked = $false
                $chkVerbose.Checked = $false
                $chkAnyForeground.Checked = $false
                $chkStartOnDotaForeground.Checked = $true
                $chkStopAfter.Checked = $true
                $numPoll.Value = 450
                $numStable.Value = 3
                $numCooldown.Value = 15
                $lblModeHint.Text = 'Clicks when a match is detected, then stops.'
                Set-CustomOptionsVisible $false
            }
            'Test: detect only' {
                $chkNoClick.Checked = $true
                $chkVerbose.Checked = $true
                $chkAnyForeground.Checked = $false
                $chkStartOnDotaForeground.Checked = $true
                $chkStopAfter.Checked = $true
                $numPoll.Value = 450
                $numStable.Value = 3
                $numCooldown.Value = 15
                $lblModeHint.Text = 'Logs and beeps when detected, but does not click.'
                Set-CustomOptionsVisible $false
            }
            'Fast: lower delay' {
                $chkNoClick.Checked = $false
                $chkVerbose.Checked = $false
                $chkAnyForeground.Checked = $false
                $chkStartOnDotaForeground.Checked = $true
                $chkStopAfter.Checked = $true
                $numPoll.Value = 200
                $numStable.Value = 2
                $numCooldown.Value = 10
                $lblModeHint.Text = 'Faster polling with fewer stable hits.'
                Set-CustomOptionsVisible $false
            }
            default {
                $lblModeHint.Text = 'Show all options and use these values exactly.'
                Set-CustomOptionsVisible $true
            }
        }
    }
    finally {
        $state.ApplyingMode = $false
        Update-ConfigurationText
    }
}

$cmbAcceptMode.Add_SelectedIndexChanged({
    if ($cmbAcceptMode.SelectedItem) {
        Set-AcceptMode -Mode ([string]$cmbAcceptMode.SelectedItem)
    }
})

$markCustom = {
    if (-not $state.ApplyingMode -and $cmbAcceptMode.SelectedItem -and [string]$cmbAcceptMode.SelectedItem -ne 'Custom') {
        $cmbAcceptMode.SelectedItem = 'Custom'
    }
    elseif (-not $state.ApplyingMode) {
        Update-ConfigurationText
    }
}

$chkNoClick.Add_CheckedChanged($markCustom)
$chkVerbose.Add_CheckedChanged($markCustom)
$chkAnyForeground.Add_CheckedChanged($markCustom)
$chkStartOnDotaForeground.Add_CheckedChanged($markCustom)
$chkStopAfter.Add_CheckedChanged($markCustom)
$numPoll.Add_ValueChanged($markCustom)
$numStable.Add_ValueChanged($markCustom)
$numCooldown.Add_ValueChanged($markCustom)

$cmbLobbyMode.Add_SelectedIndexChanged({
    if ($cmbLobbyMode.SelectedItem) {
        Set-LobbyMode -Mode ([string]$cmbLobbyMode.SelectedItem)
    }
})

$markLobbyCustom = {
    if (-not $state.ApplyingMode -and $cmbLobbyMode.SelectedItem -and [string]$cmbLobbyMode.SelectedItem -ne 'Custom') {
        $cmbLobbyMode.SelectedItem = 'Custom'
    }
    elseif (-not $state.ApplyingMode) {
        Update-ConfigurationText
    }
}

$cmbGameMode.Add_TextChanged($markLobbyCustom)
$cmbGameMode.Add_SelectedIndexChanged($markLobbyCustom)
$btnSaveGameMode.Add_Click({ Save-SelectedGameMode })
$chkLobbyDryRun.Add_CheckedChanged($markLobbyCustom)
$numStepDelay.Add_ValueChanged($markLobbyCustom)

$cmbRecorderTool.Add_TextChanged({
    if (-not $state.ApplyingMode) {
        $previousDefault = Get-RecorderDefaultOutput -Tool $state.LastRecorderToolText
        $currentTool = Get-SelectedRecorderTool
        if ([string]::IsNullOrWhiteSpace($txtRecorderOutput.Text) -or $txtRecorderOutput.Text -eq $previousDefault) {
            $txtRecorderOutput.Text = Get-RecorderDefaultOutput -Tool $currentTool
        }
        $state.LastRecorderToolText = $currentTool
        Update-ConfigurationText
    }
})
$cmbRecorderTool.Add_SelectedIndexChanged({
    if (-not $state.ApplyingMode) {
        $currentTool = Get-SelectedRecorderTool
        $txtRecorderOutput.Text = Get-RecorderDefaultOutput -Tool $currentTool
        $state.LastRecorderToolText = $currentTool
        Update-ConfigurationText
    }
})
$btnSaveRecorderTool.Add_Click({ Save-SelectedRecorderTool })
$txtRecorderOutput.Add_TextChanged({ Update-ConfigurationText })

$chkSiriSupport.Add_CheckedChanged({
    if ($chkSiriSupport.Checked) {
        Start-SiriSupport
    }
    else {
        Stop-SiriSupport
    }
})

$btnCopySiriUrl.Add_Click({
    try {
        $value = $txtSiriStatus.Text
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'Siri: off') {
            Add-Log 'Siri URL is not available. Enable Siri support first.'
            return
        }
        [System.Windows.Forms.Clipboard]::SetText($value)
        Add-Log "Copied Siri URL: $value"
    }
    catch {
        Add-Log "Copy Siri URL failed: $($_.Exception.Message)"
    }
})

$cmbModule.Add_SelectedIndexChanged({
    if ($cmbModule.SelectedItem) {
        $state.ActiveFunction = ''
        $state.RecorderClicks = @()
        Set-ActiveModule -Module ([string]$cmbModule.SelectedItem)
    }
})

Set-AcceptMode -Mode 'Ready: click once'
Set-GameModeItems -Selected 'DOTA2 IM'
Set-RecorderToolItems -Selected 'new-tool'
Set-LobbyMode -Mode 'Run sequence'
Set-ActiveModule -Module 'Auto Accept'

$btnStart.Add_Click({
    try {
        if ($state.ActiveFunction -eq 'OperationRecorder') {
            Finish-OperationRecorder
            return
        }

        if ($null -ne $state.Process -and -not $state.Process.HasExited) {
            Add-Log 'A tool is already running.'
            return
        }

        if ([string]$cmbModule.SelectedItem -eq 'Operation Recorder') {
            Start-OperationRecorder
            return
        }
        elseif ([string]$cmbModule.SelectedItem -eq 'Create Lobby') {
            [void](Start-CreateLobbyWorker -Trigger 'manual')
            return
        }
        else {
            [void](Start-AutoAcceptWorker -Trigger 'manual')
            return
        }
    }
    catch {
        Add-Log "Start failed: $($_.Exception.Message)"
    }
})

$btnStop.Add_Click({
    if ($state.ActiveFunction -eq 'OperationRecorder') {
        Stop-OperationRecorder
        return
    }
    if ([string]$cmbModule.SelectedItem -eq 'Auto Accept') {
        $state.AutoAcceptSuppressUntilDotaLeaves = $true
    }
    Stop-Worker
})

$btnCalibrate.Add_Click({
    try {
        $module = [string]$cmbModule.SelectedItem

        if ($state.ActiveFunction -eq 'Calibration') {
            Stop-CalibrationRecorder
            return
        }
        if ($state.ActiveFunction -eq 'OperationRecorder') {
            Stop-OperationRecorder
            return
        }

        if ($module -eq 'Operation Recorder') {
            $outputPath = $txtRecorderOutput.Text
            if (-not [System.IO.Path]::IsPathRooted($outputPath)) {
                $outputPath = Join-Path $projectRoot $outputPath
            }
            if (-not (Test-Path -LiteralPath $outputPath)) {
                [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath))
                [pscustomobject]@{
                    tool = Get-SelectedRecorderTool
                    source = 'operation-recorder'
                    steps = @()
                } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $outputPath -Encoding UTF8
            }
            Start-Process -FilePath 'notepad.exe' -ArgumentList $outputPath
            Add-Log 'Opened recorder output JSON.'
            return
        }

        $tool = if ($module -eq 'Create Lobby') { 'Create Lobby' } else { 'Auto Accept' }
        Start-CalibrationRecorder -Tool $tool
    }
    catch {
        Add-Log "Calibration failed: $($_.Exception.Message)"
    }
})

$btnOpenFolder.Add_Click({
    try { Start-Process -FilePath $projectRoot }
    catch { Add-Log "Open folder failed: $($_.Exception.Message)" }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    try {
        if ($state.Closing) { return }
        if (Test-Path -LiteralPath $focusSignalPath) {
            $focusSignal = Get-Content -LiteralPath $focusSignalPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($focusSignal) -and $focusSignal -ne $state.FocusSignal) {
                $state.FocusSignal = $focusSignal
                Invoke-SelfFocus
            }
        }
        Sync-WorkerLog
        Poll-SiriSupport
        $foregroundProcessName = Get-ForegroundProcessName
        $isDotaForeground = $foregroundProcessName -ieq 'dota2'
        $state.LastForegroundProcessName = $foregroundProcessName

        if ($null -eq $state.LastForegroundWasDota) {
            $state.LastForegroundWasDota = $isDotaForeground
        }
        else {
            $wasDotaForeground = [bool]$state.LastForegroundWasDota
            $state.LastForegroundWasDota = $isDotaForeground

            if ($isDotaForeground -and -not $wasDotaForeground) {
                $state.LastForegroundTransition = 'outside -> dota2'
                $cursorStatus = Get-CursorWorkingAreaStatus
                $state.LastUserFocusLabel = $cursorStatus.Label
                $state.LastUserFocusIsOverDota = [bool]$cursorStatus.IsOverDota
                $focusIsOutsideDota = Test-CursorOutsideDotaWorkingArea
                if ($focusIsOutsideDota -and
                    [string]$cmbModule.SelectedItem -eq 'Auto Accept' -and
                    $chkStartOnDotaForeground.Checked -and
                    -not $state.AutoAcceptSuppressUntilDotaLeaves -and
                    [string]::IsNullOrWhiteSpace($state.ActiveFunction) -and
                    ($null -eq $state.Process -or $state.Process.HasExited)) {
                    [void](Start-AutoAcceptWorker -Trigger 'dota2 foreground signal' -ForceAllowAnyForeground $true)
                }
            }
            elseif (-not $isDotaForeground -and $wasDotaForeground) {
                $processLabel = if ([string]::IsNullOrWhiteSpace($foregroundProcessName)) { 'outside' } else { $foregroundProcessName }
                $state.LastForegroundTransition = "dota2 -> $processLabel"
            }
        }
        Update-ForegroundStatus -ProcessName $foregroundProcessName

        if (-not $isDotaForeground) {
            $state.AutoAcceptSuppressUntilDotaLeaves = $false
        }

        if ($state.ActiveFunction -eq 'Calibration') {
            $isMouseDown = (([Dota2HelperWindow]::GetAsyncKeyState([Dota2HelperWindow]::VK_LBUTTON) -band 0x8000) -ne 0)
            if (-not $isMouseDown) {
                $state.CalibrationIgnoreUntilUp = $false
            }
            elseif (-not $state.CalibrationWasMouseDown -and -not $state.CalibrationIgnoreUntilUp) {
                Record-CalibrationClick
            }
            $state.CalibrationWasMouseDown = $isMouseDown
        }
        elseif ($state.ActiveFunction -eq 'OperationRecorder') {
            $isMouseDown = (([Dota2HelperWindow]::GetAsyncKeyState([Dota2HelperWindow]::VK_LBUTTON) -band 0x8000) -ne 0)
            if (-not $isMouseDown) {
                $state.RecorderIgnoreUntilUp = $false
            }
            elseif (-not $state.RecorderWasMouseDown -and -not $state.RecorderIgnoreUntilUp) {
                Record-OperationClick
            }
            $state.RecorderWasMouseDown = $isMouseDown
        }
        if ($null -ne $state.Process -and $state.Process.HasExited) {
            Sync-WorkerLog
            Add-Log "Capture process exited with code $($state.Process.ExitCode)."
            $state.Process.Dispose()
            $state.Process = $null
            if ($state.AutoAcceptStartedFromSignal -and $isDotaForeground) {
                $state.AutoAcceptSuppressUntilDotaLeaves = $true
            }
            $state.AutoAcceptStartedFromSignal = $false
            Set-RunningState $false
        }
        $lblCalibration.Text = Get-CalibrationText
    }
    catch {
        Add-Log "Timer error: $($_.Exception.Message)"
    }
})
$timer.Start()

$form.Add_FormClosing({
    $state.Closing = $true
    $timer.Stop()
    Stop-SiriSupport
    Stop-Worker
    $timer.Dispose()
    try { $helperMutex.ReleaseMutex() } catch {}
    $helperMutex.Dispose()
})

Set-Content -LiteralPath $runtimeLogPath -Value '' -Encoding UTF8
$state.LogOffset = 0
Add-Log 'GUI ready.'
[void]$form.ShowDialog()

