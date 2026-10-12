param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$FixtureRoot = (Join-Path ([System.IO.Path]::GetTempPath()) ('bizarre-gems-records-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixture = [System.IO.Path]::GetFullPath($FixtureRoot)
if (Test-Path -LiteralPath $fixture) {
    if (@(Get-ChildItem -LiteralPath $fixture -Force).Count -ne 0) { throw 'FixtureRoot must be an empty directory.' }
}
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
foreach ($folder in @('scripts','scenes','assets','tests')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $fixture -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'icon.png') -Destination $fixture
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$config = $config -replace '(?m)^_mcp_game_helper=.*\r?\n', ''
$config = $config -replace '(?m)^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)', 'enabled=PackedStringArray()'
$config = $config -replace '(?m)^config/name=.*', 'config/name="Bizarre Gems Records Fixture"'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $fixture 'project.godot'), $config, $utf8)
New-Item -ItemType Directory -Force -Path (Join-Path $fixture '.test-user') | Out-Null
foreach ($entry in @(@('save.gd','save.cfg'),@('progress.gd','progress.cfg'))) {
    $path = Join-Path $fixture ('scripts/' + $entry[0])
    $source = Get-Content -LiteralPath $path -Raw
    $source = $source -replace 'const PATH := "user://[^"]+"', ('const PATH := "res://.test-user/' + $entry[1] + '"')
    [System.IO.File]::WriteAllText($path, $source, $utf8)
}
$import = Start-Process -FilePath $Godot -ArgumentList @('--headless','--path',('"' + $fixture + '"'),'--editor','--import','--quit') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture 'import.log') -RedirectStandardError (Join-Path $fixture 'import_errors.log')
if ($import.ExitCode -ne 0) { throw 'Fixture import failed; see import_errors.log.' }
foreach ($stage in @('earn','reload')) {
    $run = Start-Process -FilePath $Godot -ArgumentList @('--headless','--path',('"' + $fixture + '"'),'--script','res://tests/test_mode_records.gd','--',('--records-stage=' + $stage)) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture ($stage + '.log')) -RedirectStandardError (Join-Path $fixture ($stage + '_errors.log'))
    if ($run.ExitCode -ne 0) { throw ('Record test failed: ' + $stage + '; see its error log.') }
}
Write-Output ('Record tests passed. Isolated save files and JSON reports: ' + $fixture + '/.test-user')
