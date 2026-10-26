"""PreToolUse guard for this repository (see CLAUDE.md, "Repository and git").

Blocks, with exit code 2 and a reason Claude reads:
- risky git: push, force, reset --hard, merge (except --abort), branch deletion,
  bare stash, anything about the `upstream` remote, reading all refs (--all, -a, -r);
- writes to the user's own files and to this guard itself.
The user runs such commands themselves or temporarily disables the hook.
"""
import json
import re
import sys

PROTECTED = ("export_presets.cfg", "project.godot", ".claude/settings.json", ".claude/hooks/guard.py")

GIT_RULES = [
    (r"\bgit\b[^\n;&|]*\bpush\b", "git push needs the user's explicit OK"),
    (r"\bgit\b[^\n;&|]*(--force\b|--force-with-lease|\s-f\b)", "forced git operations need the user's OK"),
    (r"\bgit\b[^\n;&|]*\breset\b[^\n;&|]*--hard", "git reset --hard needs the user's OK"),
    (r"\bgit\b[^\n;&|]*\bmerge\b(?![^\n;&|]*--abort)", "merges (into integration or elsewhere) need the user's OK"),
    (r"\bgit\b[^\n;&|]*\bbranch\b[^\n;&|]*(\s-d\b|\s-D\b|--delete)", "deleting branches needs the user's OK"),
    (r"\bgit\s+stash(\s*$|\s*[;&|]|\s+(pop|drop|clear)\b)", "bare git stash is shared between worktrees; use a WIP commit"),
    (r"\b(git|gh)\b[^\n;&|]*(\bupstream\b|electrocrem/)", "the upstream remote is off limits until the user lifts the ban"),
    (r"\bgit\b[^\n;&|]*\b(log|rev-list|shortlog|branch|for-each-ref|show-ref|describe|reflog)\b[^\n;&|]*(--all\b|--remotes\b|\s-a\b|\s-r\b)",
     "reading all refs includes upstream/*; name the refs you need instead"),
]

WRITE_VERBS = (r"(\brm\b|\bmv\b|\bcp\b|(?<![0-9&])>|\bsed\s+-i|\btee\b|\btruncate\b|"
               r"\bgit\s+(checkout|restore|reset|rm|add|stash|commit\s+-a)\b|"
               r"Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item|Rename-Item|New-Item|WriteAll)")


def block(reason: str) -> None:
    sys.stderr.buffer.write(("Blocked by .claude/hooks/guard.py: " + reason +
                             ". Ask the user instead.\n").encode("utf-8"))
    sys.exit(2)


def norm(path: str) -> str:
    return path.replace("\\", "/").lower()


def main() -> None:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    tool = data.get("tool_name", "")
    inp = data.get("tool_input", {}) or {}
    if tool in ("Bash", "PowerShell"):
        cmd = inp.get("command", "") or ""
        for pattern, reason in GIT_RULES:
            if re.search(pattern, cmd, re.IGNORECASE):
                block(reason)
        low = norm(cmd)
        if any(p in low for p in PROTECTED) and re.search(WRITE_VERBS, cmd, re.IGNORECASE):
            block("this command may change a protected file (%s)" % ", ".join(p for p in PROTECTED if p in low))
    elif tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = norm(inp.get("file_path", "") or inp.get("notebook_path", "") or "")
        for p in PROTECTED:
            if path == p or path.endswith("/" + p):
                block("%s is the user's file (or the guard itself)" % p)
    sys.exit(0)


if __name__ == "__main__":
    main()
