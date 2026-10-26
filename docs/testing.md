# Testing

All automated checks go through `tools/test_isolated.ps1` (PowerShell 7). It copies the
project to `build/verification/<id>/`, runs Godot with its own profile and Dummy audio,
and keeps logs there (`suite-N/stdout.log`, `stderr.log`). The real player profile and the
editor are never touched. Full background: tests/README.md.

```powershell
$g = 'G:/Software/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
```

## Regression set (end of every stage, about 3 minutes)
```powershell
./tools/test_isolated.ps1 -Godot $g -Scripts 'res://tests/test_logic.gd','res://tests/run_combo_suite.gd','res://tests/run_strike_accounting.gd','res://tests/smoke_ui.gd','res://tests/test_bright_run.gd','res://tests/run_flow_suite.gd'
```

## Visual and HUD checks (only when drawing or layout changed)
```powershell
./tools/test_isolated.ps1 -Godot $g -Render -Scripts 'res://tests/run_visual_suite.gd','res://tests/test_hud_layout.gd','res://tests/test_hud_routes.gd'
```
- Rendered runs open a real window. Mouse movement over it or focus loss changes the
  captures (hover highlights, auto-pause) and fails pixel-equality checks at random.
  Launch them from Bash as `pwsh -NoProfile -Command "./tools/test_isolated.ps1 …"` and
  keep the mouse away; rerun once before assuming a regression.
- Several visual checks pin the current art (e.g. "faceted gem mapping", pixel-identical
  palette captures). A deliberate visual change will fail them; updating them is a test
  change and needs the user's approval.

## Other flags
- `-UserArgs '<arg>'` passes arguments after `--` to the game (`OS.get_cmdline_user_args()`).
- `-ReferenceMenu`, `-ReferenceVisuals`, `-ReferenceHud`: comparisons with pinned
  refinement drawing code (see tests/README.md).
- `-Assets` (asset generator) currently fails: `tools/svg_to_png.cjs` cannot find a Node
  module. Unrelated to game code.

## Writing a check
- Suites are SceneTree scripts under `tests/`; the runner knows each suite's completion
  marker (`*_DONE`) in `tools/test_isolated.ps1`. New suites need a marker there or they
  pass on exit code alone.
- `Save.sound` is false in suites; set it true only around the call you test and stop the
  `Sfx` players afterwards, or Godot reports resources still in use at exit.

## Lint
`tools/lint.sh` (gdtoolkit, rules in `gdlintrc`). gdlint is not installed; the script then
skips with a message. gdtoolkit does not parse all Godot 4.7 syntax and skips such files.
