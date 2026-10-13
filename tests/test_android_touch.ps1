param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$FixtureRoot = (Join-Path ([IO.Path]::GetTempPath()) ('bizarre-touch-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixture = [IO.Path]::GetFullPath($FixtureRoot)
if ($fixture.TrimEnd('\') -eq $projectRoot.TrimEnd('\') -or $fixture.StartsWith($projectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'FixtureRoot must be outside the live project.'
}
if ((Test-Path -LiteralPath $fixture) -and @(Get-ChildItem -LiteralPath $fixture -Force).Count -ne 0) {
    throw 'FixtureRoot must be an empty directory.'
}
New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'scripts'), (Join-Path $fixture 'tests'), (Join-Path $fixture 'assets') | Out-Null
foreach ($folder in @('gems','tiles','ui','fx')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('assets/' + $folder)) -Destination (Join-Path $fixture 'assets') -Recurse
}
foreach ($name in @('board_logic','special_gem_art')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('scripts/' + $name + '.gd')) -Destination (Join-Path $fixture 'scripts')
}
$utf8 = New-Object Text.UTF8Encoding($false)
$boardSource = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/board_view.gd') -Raw
# Enable only the Android platform gate in the isolated copy, never in production.
[IO.File]::WriteAllText((Join-Path $fixture 'scripts/board_view.gd'), $boardSource.Replace('OS.has_feature("android")', 'true'), $utf8)
[IO.File]::WriteAllText((Join-Path $fixture 'scripts/desktop_board_view.gd'), $boardSource.Replace('class_name BoardView', 'class_name DesktopBoardView'), $utf8)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_android_touch.gd') -Destination (Join-Path $fixture 'tests')
# No Save, SDK, main scene or real Progress autoload: these checks cannot access
# player saves, award progress, or submit scores. The view only needs two constants.
[IO.File]::WriteAllText((Join-Path $fixture 'scripts/progress_stub.gd'), "extends Node`nconst COSMETICS_ENABLED = false`nconst BASE_LOOK = 0`n", $utf8)
$config = @'
config_version=5
[application]
config/name="Bizarre Gems Touch Fixture"
[autoload]
Progress="*res://scripts/progress_stub.gd"
[display]
window/size/viewport_width=480
window/size/viewport_height=854
[input_devices]
pointing/emulate_mouse_from_touch=false
[rendering]
renderer/rendering_method="gl_compatibility"
'@
[IO.File]::WriteAllText((Join-Path $fixture 'project.godot'), $config, $utf8)
$import = Start-Process -FilePath $Godot -WorkingDirectory $fixture -ArgumentList @('--headless','--path',('"' + $fixture + '"'),'--editor','--import','--quit') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture 'import.log') -RedirectStandardError (Join-Path $fixture 'import_errors.log')
if ($import.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $fixture 'import_errors.log') -Pattern '^(SCRIPT ERROR|ERROR):')) { throw ('Fixture import failed: ' + $fixture) }
$run = Start-Process -FilePath $Godot -WorkingDirectory $fixture -ArgumentList @('--headless','--path',('"' + $fixture + '"'),'--quit-after','300','--script','res://tests/test_android_touch.gd') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture 'touch.log') -RedirectStandardError (Join-Path $fixture 'touch_errors.log')
$result = Get-Content -LiteralPath (Join-Path $fixture 'touch.log') | Select-String 'ANDROID_TOUCH'
$result | ForEach-Object { $_.Line }
Write-Output ('Isolated fixture: ' + $fixture)
if (-not $result -or $run.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $fixture 'touch_errors.log') -Pattern '^(SCRIPT ERROR|ERROR):')) { throw ('Touch checks failed: ' + $fixture) }
