#!/usr/bin/python3

import json
import os
import re
import sys
from typing import List

# TODO: Force a compile to happen if bazel compiled the target (might require a stub source file and it might trigger all?)

_SWIFT_FILES_PATTERN = r"(.*?(/Index/Build)?)/Intermediates\.noindex/.*\.build/bazel-out/([^/]+)/bin/(external/([^/]+)/)?(.*)/([^/]+)/Objects-normal/[^/]+/[^/]+$"

def _main() -> None:
    if sys.argv[1:] == ["-v"]:
        os.system("swiftc -v")
        return

    # TODO: Iterate over the arguments once
    _touch_deps_files(sys.argv)
    _touch_swiftmodule_artifacts(sys.argv)
    _write_output_groups_file(sys.argv)


def _touch_deps_files(args: List[str]) -> None:
    "Touch the Xcode-required .d files"
    flag = args.index("-output-file-map")
    output_file_map_path = args[flag + 1]

    with open(output_file_map_path) as f:
        output_file_map = json.load(f)

    d_files = [
        entry["dependencies"]
        for entry in output_file_map.values()
        if "dependencies" in entry
    ]

    for d_file in d_files:
        _touch(d_file)


def _touch_swiftmodule_artifacts(args: List[str]) -> None:
    "Touch the Xcode-required .swift{module,doc,sourceinfo} files"
    flag = args.index("-emit-module-path")
    swiftmodule_path = args[flag + 1]
    swiftdoc_path = _replace_ext(swiftmodule_path, "swiftdoc")
    swiftsourceinfo_path = _replace_ext(swiftmodule_path, "swiftsourceinfo")

    _touch(swiftmodule_path)
    _touch(swiftdoc_path)
    _touch(swiftsourceinfo_path)


def _touch(path: str) -> None:
    # Don't open with "w" mode, that truncates the file if it exists.
    open(path, "a")


def _replace_ext(path: str, extension: str) -> str:
    name, _ = os.path.splitext(path)
    return ".".join((name, extension))

def _write_output_groups_file(args: List[str]) -> None:
    flag = args.index("-output-file-map")
    output_file_map_path = args[flag + 1]

    match = re.search(_SWIFT_FILES_PATTERN, output_file_map_path)
    if not match:
        print("Unable to parse paths", file=sys.stderr)
        sys.exit(1)

    if match.group(1):
        mode = "i"
    else:
        mode = "b"

    build_dir = match.group(1)
    bazel_build_output_groups = f"{build_dir}/bazel_build_output_groups"

    repo = match.group(4)
    prefix = f"@{repo}//" if repo else ""
    output_group = f"""\
{mode} {prefix}{match.group(5)}:{match.group(6)} {match.group(2)}
"""

    with open(bazel_build_output_groups, "w", encoding = "utf8") as f:
        f.write(output_group)


if __name__ == "__main__":
    _main()
