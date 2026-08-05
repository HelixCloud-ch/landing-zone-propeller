"""Check that the baked provider mirror satisfies every framework project.

Runs inside the deploy-runner image container with the repo mounted at /repo.
Exits 0 if all constraints are satisfied, 1 if any are missing.
"""

import glob
import os
import re
import sys

MIRROR = "/opt/tf-providers/registry.terraform.io"
DEFERRED = {"terraform-redhat/rhcs", "hetznercloud/hcloud"}


def parse_version(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.split("."))


def satisfies(ver_str: str, constraint: str) -> bool:
    """Check if ver_str satisfies a terraform version constraint."""
    constraint = constraint.strip().strip('"')
    ver = parse_version(ver_str)
    if constraint.startswith("~>"):
        parts = constraint[2:].strip().split(".")
        lower = tuple(int(x) for x in parts)
        while len(lower) < len(ver):
            lower = lower + (0,)
        upper_parts = [int(x) for x in parts]
        if len(upper_parts) == 1:
            upper = (upper_parts[0] + 1,)
        else:
            upper_parts[-2] += 1
            upper_parts[-1] = 0
            upper = tuple(upper_parts)
        while len(upper) < len(ver):
            upper = upper + (0,)
        return lower <= ver < upper
    elif constraint.startswith(">="):
        lower = parse_version(constraint[2:].strip())
        return ver >= lower
    else:
        return ver == parse_version(constraint)


def mirror_versions(ns: str, name: str) -> list[str]:
    """List versions available in the mirror for a provider."""
    path = os.path.join(MIRROR, ns, name)
    if not os.path.isdir(path):
        return []
    versions: set[str] = set()
    for entry in os.listdir(path):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            versions.add(entry)
        elif entry.endswith(".zip"):
            # terraform-provider-<name>_<ver>_<os>_<arch>.zip
            parts = entry.rsplit("_", 2)
            if len(parts) >= 2:
                name_ver = parts[0]
                ver_part = name_ver.rsplit("_", 1)
                if len(ver_part) == 2:
                    versions.add(ver_part[1])
    return list(versions)


def main() -> int:
    rc = 0
    vtfs = sorted(
        glob.glob("/repo/platform/projects/*/terraform/versions.tf")
        + glob.glob("/repo/platform/shared/modules/*/versions.tf")
        + glob.glob("/repo/landing-zone/projects/*/terraform/versions.tf")
        + glob.glob("/repo/autopilot/terraform/versions.tf")
    )
    for vtf in vtfs:
        proj = vtf.removeprefix("/repo/")
        with open(vtf) as f:
            content = f.read()
        for m in re.finditer(r'source\s*=\s*"([^"]+)"', content):
            src = m.group(1)
            if src in DEFERRED:
                print(f"  skip ({src}): {proj}")
                continue
            after = content[m.end():]
            vm = re.search(r'version\s*=\s*"([^"]+)"', after[:200])
            if not vm:
                continue
            constraint = vm.group(1)
            ns, name = src.split("/", 1)
            versions = mirror_versions(ns, name)
            if any(satisfies(v, constraint) for v in versions):
                print(f"  ok:   {proj} ({src} {constraint})")
            else:
                print(
                    f"  FAIL: {proj} ({src} {constraint} not satisfied by mirror: {versions})"
                )
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
