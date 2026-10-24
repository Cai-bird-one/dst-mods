"""Run the real PVP chat wrapper against the installed ChatHistory in Lua 5.1.

Python requires lupa; pass --lupa-path for an isolated temporary installation.
Engine globals and team state are stubs; this is not a live multiplayer test.
"""

import argparse
from pathlib import Path
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path)
    args = parser.parse_args()
    if args.lupa_path:
        sys.path.insert(0, str(args.lupa_path))
    from lupa.lua51 import LuaRuntime

    root = Path(__file__).resolve().parents[3]
    with zipfile.ZipFile(root.parent / "data/databundles/scripts.zip") as archive:
        native = archive.read("scripts/chathistory.lua").decode("utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().native_chat_source = native
    lua.globals().pvp_chat_source = (root / "pvp/scripts/src/team/chat.lua").read_text(encoding="utf-8")
    count = lua.execute(Path(__file__).with_suffix(".lua").read_text(encoding="utf-8"))
    print(f"PASS ChatHistory: {count} assertions ({lua.eval('_VERSION')})")


if __name__ == "__main__":
    main()
