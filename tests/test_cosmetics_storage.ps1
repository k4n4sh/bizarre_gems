param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
# Production scripts, isolated project/profile, no editor plugin or network SDK.
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('bizarre-cosmetics-' + [guid]::NewGuid().ToString('N'))
$profileName = [IO.Path]::GetFileName($fixture)
$profile = Join-Path $env:APPDATA $profileName
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts'), $profile | Out-Null
try {
    foreach ($name in @('progress', 'save', 'yandex', 'combo_experiment', 'board_logic')) {
        Copy-Item -LiteralPath (Join-Path $repo "scripts/$name.gd") -Destination (Join-Path $fixture "scripts/$name.gd")
    }
    $profileSetting = $profile.Replace('\', '/')
    $project = @"
config_version=5
[application]
config/name="Bizarre Gems Cosmetics Fixture"
config/use_custom_user_dir=true
config/custom_user_dir_name="$profileName"
[tests]
expected_profile="$profileSetting"
[autoload]
Yandex="*res://scripts/yandex.gd"
Save="*res://scripts/save.gd"
Progress="*res://scripts/progress.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
"@
    [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'), $project, $utf8)
    $test = @'
extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var p = root.get_node("Progress")
	var s = root.get_node("Save")
	check(OS.get_user_data_dir() == ProjectSettings.get_setting("tests/expected_profile"), "isolated profile")
	if not failures.is_empty():
		printerr({"failures":failures,"actual":OS.get_user_data_dir(),"expected":ProjectSettings.get_setting("tests/expected_profile")})
		quit(1)
		return
	if "--reload" not in OS.get_cmdline_user_args():
		# Write an old-format save with a purchased, selected alternative.
		var cfg := ConfigFile.new()
		cfg.set_value("shop", "look", 3)
		cfg.set_value("shop", "owned", [0, 3, 6])
		cfg.set_value("shop", "crystals", 321)
		cfg.set_value("levels", "stars", {1: 3})
		cfg.set_value("pass", "season", p.season_id())
		cfg.set_value("pass", "xp", 3000)
		cfg.set_value("pass", "claimed", [])
		cfg.set_value("pass", "hints", 2)
		cfg.set_value("meta", "local_scores", {"score_bright": [{"score":777,"date":"fixture"}]})
		check(cfg.save(p.PATH) == OK, "fixture written")
		p._ready()
		check(p.look == 3 and p.active_look() == 0, "old selected look preserved but not rendered")
		check(p.crystals == 321 and p.owns(3) and p.owns(6), "purchases and currency loaded")
		check(p.owns(9) and p.owns(10), "earned pass packs banked on load")
		check(p.claim_pass(10).is_empty(), "banked reward cannot be claimed again")
		check(p.claim_pass(5) == {"kind":"hints","n":3}, "hints paid")
		check(p.claim_pass(15) == {"kind":"crystals","n":100}, "crystals paid")
		var today := Time.get_date_string_from_system(true)
		p.gift_date = Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today) - 86400)
		p.streak = 6
		check(p.open_gift().crystals == 40 and p.owns(8), "gift currency and entitlement paid")
		# Existing cloud merge rules retain the local selected look and union ownership.
		p.merge({"owned":[0,4],"look":4,"crystals":500,"season":p.season_id(),"season_xp":3000})
		check(p.look == 3 and p.owns(4) and p.crystals == 500, "cloud merge preserves choice and purchases")
		s.best = 1234
		s.best_bright = 5678
		s.store()
		p._save()
	else:
		check(p.look == 3, "selected alternative survives process restart")
		check(p.active_look() == (3 if p.COSMETICS_ENABLED else 0), "presentation follows switch after restart")
		check(p.crystals == 500 and p.hint_tokens == 5, "currency and hints persisted")
		check(p.season_xp == 3000 and p.season_claimed.has(10) and p.season_claimed.has(30), "pass progress persisted")
		check(p.season_claimed.has(5) and p.season_claimed.has(15), "noncosmetic claims persisted")
		check(p.owned == [0,3,6,9,10,8,4], "all old, banked, gift and cloud packs persisted")
		check(p.stars_for(1) == 3 and p.local_top("score_bright")[0].score == 777, "level progress and local records unchanged")
		check(s.best == 1234 and s.best_bright == 5678, "records unaffected")
		check(p.streak == 7 and p.open_gift().is_empty(), "gift persisted without double payment")
		var cloud: Dictionary = s.cloud_data()
		check(cloud.progress.look == 3 and cloud.progress.owned == p.owned and cloud.progress.crystals == 500, "cloud payload retains cosmetics and currency")
	print(JSON.stringify({"enabled":p.COSMETICS_ENABLED,"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'test.gd'), $test, $utf8)
    & $GodotPath --headless --path $fixture --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Fixture import failed' }
    & $GodotPath --headless --path $fixture --script res://test.gd
    if ($LASTEXITCODE -ne 0) { throw 'Disabled save test failed' }
    & $GodotPath --headless --path $fixture --script res://test.gd -- --reload
    if ($LASTEXITCODE -ne 0) { throw 'Disabled reload test failed' }
    $progressPath = Join-Path $fixture 'scripts/progress.gd'
    $source = [IO.File]::ReadAllText($progressPath)
    if (-not $source.Contains('const COSMETICS_ENABLED := false')) { throw 'Run with cosmetics disabled in the source project' }
    [IO.File]::WriteAllText($progressPath, $source.Replace('const COSMETICS_ENABLED := false', 'const COSMETICS_ENABLED := true'), $utf8)
    & $GodotPath --headless --path $fixture --script res://test.gd -- --reload
    if ($LASTEXITCODE -ne 0) { throw 'Reenabled reload test failed' }
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolvedFixture)).StartsWith('bizarre-cosmetics-')) {
        throw 'Refusing cleanup outside the generated fixture directory'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    $resolvedProfile = [IO.Path]::GetFullPath($profile)
    $appDataRoot = [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\') + '\'
    if ($resolvedProfile -ne ($appDataRoot + $profileName) -or -not $profileName.StartsWith('bizarre-cosmetics-')) {
        throw 'Refusing cleanup outside the isolated fixture profile'
    }
    Remove-Item -LiteralPath $resolvedProfile -Recurse -Force
}
