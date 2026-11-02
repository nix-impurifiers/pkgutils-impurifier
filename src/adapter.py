#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Run a native pkgutils transaction, then reconcile Nix application intent."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile


def requirements(archive):
    with tarfile.open(archive) as source:
        found = [entry for entry in source.getmembers()
                 if entry.name.removeprefix("./").startswith("usr/share/pkgutils-impurifier/requirements/")
                 and entry.isfile()]
        if len(found) > 1:
            raise ValueError("multiple package requirement records")
        if not found:
            return
        if found[0].size > 65536:
            raise ValueError("oversized package requirements")
        value = json.load(source.extractfile(found[0]))
    if (not isinstance(value, dict) or set(value) != {"schema", "dependencies", "runtimeVersion"}
            or value["schema"] != 1 or not isinstance(value["dependencies"], list)
            or not all(isinstance(name, str) and re.fullmatch(r"[a-z0-9][a-z0-9+_.-]*", name)
                       for name in value["dependencies"])):
        raise ValueError("invalid package requirements")
    installed = {line.split()[0] for line in subprocess.check_output(
        ["pkginfo", "-i"], text=True).splitlines() if line.strip()}
    missing = set(value["dependencies"]) - installed
    if missing:
        raise ValueError("install native dependencies first: " + ", ".join(sorted(missing)))
    required = value["runtimeVersion"]
    if required is not None:
        if not isinstance(required, str) or not re.fullmatch(r"[0-9]+(\.[0-9]+)*", required):
            raise ValueError("invalid minimum runtime version")
        actual = Path("/usr/share/pkgutils-impurifier/runtime-version").read_text().strip()
        if tuple(map(int, actual.split("."))) < tuple(map(int, required.split("."))):
            raise ValueError("upgrade the native runtime first")


def main():
    if any(arg in {"-r", "--root"} or arg.startswith("--root=") for arg in sys.argv[1:]):
        raise ValueError("foreign roots/options cannot activate the host")
    actions = {"install", "upgrade", "remove", "check", "native-add", "native-remove"}
    if len(sys.argv) < 3 or sys.argv[1] not in actions:
        raise ValueError("usage: pkgutils-impurifier {install|upgrade|remove|check} package")
    action, package = sys.argv[1], sys.argv[-1]
    options = sys.argv[2:-1]
    if (options and action != "native-add") or any(
            option not in {"-u", "--upgrade", "-f", "--force"} for option in options):
        raise ValueError("unsupported native options")
    if package.startswith("-"):
        raise ValueError("foreign roots/options cannot activate the host")
    if action in {"remove", "native-remove"}:
        command = ["pkgrm", package]
    else:
        requirements(package)
        if action == "check":
            return 0
        if action == "native-add":
            command = ["pkgadd", *options, package]
        else:
            name = Path(package).name.split("#", 1)[0]
            installed = {line.split()[0] for line in subprocess.check_output(
                ["pkginfo", "-i"], text=True).splitlines() if line.strip()}
            command = ["pkgadd"] + (["-u"] if action == "upgrade" or name in installed else []) + [package]
    native_status = subprocess.run(command).returncode
    engine = Path("/usr/sbin/nix-profile-engine")
    activation_status = subprocess.run([str(engine), "reconcile"]).returncode if engine.exists() else 0
    return native_status or activation_status


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print("pkgutils-impurifier: " + str(error), file=sys.stderr)
        sys.exit(1)
