param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$FixtureRoot = (Join-Path ([System.IO.Path]::GetTempPath()) ('bizarre-gems-bonus-' + [guid]::NewGuid().ToString('N'))),
    [string[]]$Suites = @('test_classic_bonus_combos','test_classic_balance','test_special_combo','test_strike_accounting','test_bright_run','test_mode_transition','test_visual_unification')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixture = [System.IO.Path]::GetFullPath($FixtureRoot)
if ($fixture.TrimEnd('\') -eq $projectRoot.TrimEnd('\') -or $fixture.StartsWith($projectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'FixtureRoot must be outside the live project.'
}
if ((Test-Path -LiteralPath $fixture) -and @(Get-ChildItem -LiteralPath $fixture -Force).Count -ne 0) {
    throw 'FixtureRoot must be an empty directory.'
}
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
foreach ($folder in @('scripts','scenes','assets','tests')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $fixture -Recurse
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'icon.png') -Destination $fixture
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$config = $config -replace '(?m)^_mcp_game_helper=.*\r?\n', ''
$config = $config -replace '(?m)^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)', 'enabled=PackedStringArray()'
$fixtureName = 'Bizarre Gems Color Fixture ' + [guid]::NewGuid().ToString('N')
$config = $config -replace '(?m)^config/name=.*', ('config/name="' + $fixtureName + '"')
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $fixture 'project.godot'), $config, $utf8)
New-Item -ItemType Directory -Force -Path (Join-Path $fixture '.test-user') | Out-Null
foreach ($entry in @(@('save.gd','save.cfg'),@('progress.gd','progress.cfg'))) {
    $path = Join-Path $fixture ('scripts/' + $entry[0])
    $source = Get-Content -LiteralPath $path -Raw
    if ([regex]::Matches($source, '(?m)^const PATH := "user://[^"]+"').Count -ne 1) {
        throw ('Cannot safely isolate save path: ' + $entry[0])
    }
    $source = $source -replace 'const PATH := "user://[^"]+"', ('const PATH := "res://.test-user/' + $entry[1] + '"')
    [System.IO.File]::WriteAllText($path, $source, $utf8)
}
$preflight = @'
extends SceneTree
func _initialize() -> void:
    _verify.call_deferred()
func _verify() -> void:
    var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
    var expected := OS.get_environment("BONUS_FIXTURE_ROOT").replace("\\", "/").trim_suffix("/")
    var save_path: String = root.get_node("Save").PATH
    var progress_path: String = root.get_node("Progress").PATH
    var safe := actual.to_lower() == expected.to_lower() and save_path == "res://.test-user/save.cfg" and progress_path == "res://.test-user/progress.cfg"
    print("FIXTURE_ISOLATION ", JSON.stringify({"safe":safe,"root":actual,"save":save_path,"progress":progress_path}))
    quit(0 if safe else 1)
'@
[System.IO.File]::WriteAllText((Join-Path $fixture 'tests/verify_color_fixture.gd'), $preflight, $utf8)
$import = Start-Process -FilePath $Godot -WorkingDirectory $fixture -ArgumentList @('--headless','--path',('"' + $fixture + '"'),'--editor','--import','--quit') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture 'import.log') -RedirectStandardError (Join-Path $fixture 'import_errors.log')
if ($import.ExitCode -ne 0) { throw 'Fixture import failed; see import_errors.log.' }
$env:BONUS_FIXTURE_ROOT = $fixture.Replace('\','/')
$verify = Start-Process -FilePath $Godot -WorkingDirectory $fixture -ArgumentList @('--headless','--path',('"' + $fixture + '"'),'--script','res://tests/verify_color_fixture.gd') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture 'isolation.log') -RedirectStandardError (Join-Path $fixture 'isolation_errors.log')
Remove-Item Env:\BONUS_FIXTURE_ROOT
if ($verify.ExitCode -ne 0) { throw 'Runtime isolation check failed; no suites started. See isolation.log.' }
Get-Content -LiteralPath (Join-Path $fixture 'isolation.log') | Select-String 'FIXTURE_ISOLATION' | ForEach-Object { $_.Line }
$failedSuites = @()
foreach ($suite in $Suites) {
    $env:RUNTIME_TEST_OUTPUT = Join-Path $fixture ($suite + '.json')
    $source = Get-Content -LiteralPath (Join-Path $fixture ('tests/' + $suite + '.gd')) -Raw
    $script = if ($source.StartsWith('extends SceneTree')) { 'res://tests/' + $suite + '.gd' } else { 'res://tests/run_runtime_suite.gd' }
    # This regression explicitly requires a real canvas and desktop audio driver.
    [string[]]$driverArgs = if ($suite -eq 'test_mode_transition') { @('--audio-driver','WASAPI') } else { @('--headless') }
    $run = Start-Process -FilePath $Godot -WorkingDirectory $fixture -ArgumentList (@($driverArgs) + @('--path',('"' + $fixture + '"'),'--script',$script,'--',('--suite=' + $suite))) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $fixture ($suite + '.log')) -RedirectStandardError (Join-Path $fixture ($suite + '_errors.log'))
    Write-Output ($suite + ': exit ' + $run.ExitCode)
    $runtimeErrors = Select-String -LiteralPath (Join-Path $fixture ($suite + '_errors.log')) -Pattern '^(SCRIPT ERROR|ERROR):'
    if ($run.ExitCode -ne 0 -or $runtimeErrors) { $failedSuites += $suite }
}
Remove-Item Env:\RUNTIME_TEST_OUTPUT
Write-Output ('Reports: ' + $fixture)
if ($failedSuites.Count -gt 0) { throw ('Failed suites: ' + ($failedSuites -join ', ')) }
