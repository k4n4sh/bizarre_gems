#!/usr/bin/env bash
# GDScript lint (gdtoolkit's gdlint, rules in ./gdlintrc).
#   tools/lint.sh             every tracked .gd file
#   tools/lint.sh FILE...     only these (the pre-commit hook passes the staged ones)
# A file gdtoolkit cannot parse (newer Godot 4.x syntax it does not know yet, e.g. one-line `if` inside a lambda) is reported
# as skipped, not as a failure: Godot itself is the judge of syntax (build.sh runs the tests).
set -uo pipefail
cd "$(dirname "$0")/.."
command -v gdlint >/dev/null || { echo "lint: gdlint not installed (pacman -S python-gdtoolkit / pipx install gdtoolkit), skipped" >&2; exit 0; }
if (($#)); then files=("$@"); else mapfile -t files < <(git ls-files '*.gd'); fi
((${#files[@]})) || exit 0
bad=0 skipped=()
for f in "${files[@]}"; do
    [[ -f $f ]] || continue
    out=$(gdlint "$f" 2>&1) && continue
    if grep -qE "Unexpected (token|character)|No terminal matches" <<<"$out"; then skipped+=("$f"); continue; fi
    grep -E ': Error: ' <<<"$out"
    bad=1
done
((${#skipped[@]})) && echo "lint: gdtoolkit cannot parse ${skipped[*]} (newer Godot syntax), not checked" >&2
((bad)) && { echo "lint: problems above (rules: gdlintrc)" >&2; exit 1; }
echo "lint: ok (${#files[@]} files)"
