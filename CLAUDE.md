# Bizarre Gems («Алмазная братва»)

Godot 4.7.2 (GDScript) casual puzzle for Yandex Games (web) and Android. Player-facing
description, modes and build steps: README.md. Answer the user in Russian.

## Stack and layout
- `scripts/main.gd` — game flow, modes, layout, effects orchestration (large; read by section).
- `scripts/board_logic.gd` — board rules and mode configs (`CLASSIC`, `BRIGHT`, …).
- `scripts/score_keeper.gd` — scoring, combos, timed precise/perfect, hot streak.
- `scripts/board_view.gd` — board drawing and in-field effects; `scripts/ui/` — HUD and screens.
- Autoloads: `L` (i18n, `i18n/strings.csv` RU/EN/TR), `Yandex`, `Save`, `Sfx`, `Haptics`, `Progress`.
- `scenes/main.tscn`, `scenes/game/hud_*.tscn`, `scenes/ui/*.tscn`; theme `ui/theme.tres`.

## Product rules that are not obvious from the code
- Two modes in the product: Classic and Bright Run (Daily is a Run). Legacy modes
  (levels, zen, puzzle) still exist in code; do not extend them.
- Classic: finite 23×15 board (345 slots), combo window 3.5 s, timed precise/perfect.
- Classic is landscape only on Android (`_set_orientation`); Bright Run is portrait with
  the top HUD (`Hud.layout_portrait`).
- Daily uses the UTC date (`_today()`).
- Hot streak ends only on a miss; its points come on top of all bonuses.
- Praise ladder is on (`PRAISE_LADDER` in main.gd). Praise floats up and fades, never on
  a plate; nothing may cover the field.
- Balance and game logic belong to the user: never change them as a side effect of
  other work.

## Commands
- Tests (isolated profile, Dummy audio; never run Godot on the real profile):
  `./tools/test_isolated.ps1 -Godot 'G:/Software/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' -Scripts <suites>`
  Suites, render flags and known flakiness: docs/testing.md.
- Web build: `build.sh` (runs `tools/lint.sh` first; gdlint is not installed, so lint skips).
- Android: `build_android.sh`; release helper `tools/release.sh`.

## Repository and git
- Several worktrees share one repo (`G:\Programming\bizarre_gems`, `…-integration`, …).
  Work only in the current one; never `cd` to another.
- Remotes: `origin` = k4n4sh/bizarre_gems (the user's). `upstream` = electrocrem/bizarre_gems
  (a friend's): no fetch/pull/push/ls-remote and no reading `upstream/*` refs (that
  includes `git log --all`, `git branch -a`) until the user lifts the ban.
- Ask before: push, merge into `integration`, any force or `reset --hard`, deleting branches.
- Never stage or edit the user's own uncommitted files (`export_presets.cfg`,
  `project.godot`) unless asked for that exact file.
- No bare `git stash` (the stack is shared between worktrees).
- These rules are also enforced by hooks in `.claude/settings.json` (`.claude/hooks/guard.py`).

## How we work
1. No guessing. If a short or abstract task lacks business-logic or architecture details,
   stop, ask 2–4 precise questions, agree a short plan, and write code only after "ок".
2. Iterative control. Split a large task into stages. Finish a stage, show the result,
   wait for confirmation. Never rewrite half the project in one go.
3. Protect limits. If the same error survives 2–3 attempts in a row (tests, build, lint),
   stop, describe the problem and ask how to proceed. No trial-and-error loops.
4. Visual work starts from a picture the user approved (mockup or reference), one screen
   at a time, before any Godot code. Never generate final game art procedurally.
   Details: docs/visual-work.md.
5. Run the test suites once at the end of a stage, not after every edit.
6. Report results plainly; do not praise your own screenshots — ask what the user sees.

## Docs (read when working on that area)
- docs/testing.md — test suites, flags, flaky visual checks, logs.
- docs/visual-work.md — how to approach design changes; the user's fixed visual decisions.
- tests/README.md — full history of the isolated test runner and suites.
- MANUAL_QA.md — manual checks on Windows, web and Android.
