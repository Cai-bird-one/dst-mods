"""Offline protection regression against this installation's actual Combat methods.

Requires Python + lupa (Lua 5.1); no game process or save is touched.
Run: python tools/pvp/tests/first_day_protection.py --lupa-path <temporary install>
Add --baseline-ref 836fccb to also reproduce the original damage leak.
Engine objects and the original SG reaction are stubs; this is not a live-client test.
"""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path)
    parser.add_argument("--baseline-ref", help="Optional pre-fix Git revision to reproduce the original failure")
    args = parser.parse_args()
    if args.lupa_path:
        sys.path.insert(0, str(args.lupa_path))
    from lupa.lua51 import LuaRuntime

    root = Path(__file__).resolve().parents[3]
    protection = "pvp/scripts/src/protection/player.lua"
    with zipfile.ZipFile(root.parent / "data/databundles/scripts.zip") as archive:
        combat = archive.read("scripts/components/combat.lua").decode("utf-8")
    methods = []
    for name in ("DoAttack", "DoAreaAttack", "GetAttacked", "GetAttacked_Internal"):
        match = re.search(r"^function Combat:" + name + r"\([^\n]*\)\r?\n.*?^end\b", combat, re.M | re.S)
        if not match:
            raise RuntimeError(f"Installed Combat lacks {name}; review this build before testing")
        methods.append(match.group())
    current = (root / protection).read_text(encoding="utf-8")
    harness = Path(__file__).with_suffix(".lua").read_text(encoding="utf-8")
    versions = []
    if args.baseline_ref:
        baseline = subprocess.check_output(["git", "show", f"{args.baseline_ref}:{protection}"], cwd=root).decode("utf-8")
        versions.append((f"{args.baseline_ref} baseline", baseline, True))
    versions.append(("working tree", current, False))
    for label, source, is_baseline in versions:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().Combat = lua.table()
        lua.execute("\n\n".join(methods))
        lua.globals().protection_source = source
        lua.globals().is_baseline = is_baseline
        count = lua.execute(harness)
        print(f"PASS {label}: {count} assertions ({lua.eval('_VERSION')})")
    if args.baseline_ref:
        print("PASS: installed Combat reproduced damage-without-SG-reaction before the fix; protected after it.")


if __name__ == "__main__":
    main()
