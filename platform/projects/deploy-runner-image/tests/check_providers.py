"""Check that the baked provider mirror satisfies every framework project.

Runs inside the deploy-runner image container with the repo mounted at /repo.
The provider versions come from the image's own manifest
(terraform_providers.<key>.resolved.version). Exits 0 if every constraint in a
framework versions.tf is satisfied, 1 if not.

Constraints supported: `~> X.Y[.Z]`, `>= X.Y[.Z]`, and exact versions. A
compound constraint (with a comma) is reported as unsupported.
"""

import glob
import json
import re
import sys

MANIFEST = "/etc/propeller/image.json"
# Providers that framework projects use but the mirror does not carry.
NOT_MIRRORED = {"terraform-redhat/rhcs"}


def parse_version(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.split("."))


def satisfies(ver_str: str, constraint: str) -> bool:
    """Check if ver_str satisfies a terraform version constraint."""
    constraint = constraint.strip()
    ver = parse_version(ver_str)
    if constraint.startswith("~>"):
        parts = [int(x) for x in constraint[2:].strip().split(".")]
        lower = tuple(parts)
        # ~> X.Y allows X.*; ~> X.Y.Z allows X.Y.*.
        upper = (parts[0] + 1,) if len(parts) == 1 else (*parts[:-2], parts[-2] + 1)
        return lower <= ver < upper
    if constraint.startswith(">="):
        return ver >= parse_version(constraint[2:].strip())
    return ver == parse_version(constraint)


def mirrored_versions() -> dict[str, list[str]]:
    """Map provider source to the versions the image mirrors."""
    with open(MANIFEST) as f:
        providers = json.load(f)["terraform_providers"]
    versions: dict[str, list[str]] = {}
    for entry in providers.values():
        if entry["enabled"]:
            versions.setdefault(entry["source"], []).append(entry["resolved"]["version"])
    return versions


def main() -> int:
    mirrored = mirrored_versions()
    rc = 0
    files = sorted(
        glob.glob("/repo/platform/projects/*/terraform/versions.tf")
        + glob.glob("/repo/platform/shared/modules/*/versions.tf")
        + glob.glob("/repo/landing-zone/projects/*/terraform/versions.tf")
        + glob.glob("/repo/autopilot/terraform/versions.tf")
    )
    for path in files:
        project = path.removeprefix("/repo/")
        content = open(path).read()
        for m in re.finditer(r'source\s*=\s*"([^"]+)"', content):
            source = m.group(1)
            if source in NOT_MIRRORED:
                print(f"  skip ({source}): {project}")
                continue
            vm = re.search(r'version\s*=\s*"([^"]+)"', content[m.end():][:200])
            if not vm:
                continue
            constraint = vm.group(1)
            if "," in constraint:
                print(f"  FAIL: {project} ({source} {constraint}): compound constraints are not supported")
                rc = 1
                continue
            versions = mirrored.get(source, [])
            if any(satisfies(v, constraint) for v in versions):
                print(f"  ok:   {project} ({source} {constraint})")
            else:
                print(f"  FAIL: {project} ({source} {constraint} not satisfied by mirror: {versions})")
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
