$guiScript = Join-Path $PSScriptRoot 'src\gui\Dota2Helper-GUI.ps1'
if (-not (Test-Path -LiteralPath $guiScript)) {
    throw "GUI script not found: $guiScript"
}

& $guiScript
