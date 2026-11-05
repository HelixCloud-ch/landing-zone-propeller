#!/usr/bin/env python3
"""Render the deploy-runner image manifest.

The framework declares the image in image.yaml. A consumer changes it in
image.overrides.yaml (overlay). Both files have one section per kind of
component and merge by section and key.

This tool is the only code that reads the YAML. It merges, validates, and
writes the effective manifest as JSON. The Dockerfile steps, the recipes, and
the image itself read only that JSON. The build adds a `resolved` object to
what it installs (versions, digests, checksums).

  render.py show                 print the effective manifest (JSON)
  render.py stage --out DIR      write DIR/image.json plus the files the
                                 build needs, and print a summary (and a diff
                                 with --previous)
  render.py diff OLD NEW         diff two built manifests (after a build)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

import yaml

SCHEMA_VERSION = "1"
ARCHES = ("amd64", "arm64")

KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
EXACT_VERSION_RE = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._+-]*$")
# The mirror config includes the public registry only, so no registry host.
PROVIDER_SOURCE_RE = re.compile(r"^[A-Za-z0-9-]+/[A-Za-z0-9-]+$")
TEMPLATE_RE = re.compile(r"\{(\w+)\}")
ARCHIVE_SUFFIXES = (".zip", ".tar.gz", ".tgz")

# Files that make up a python env. All are required and all go into the image.
ENV_FILES = ("pyproject.toml", "uv.lock", ".python-version")

OUTPUT_MARKER = ".renderer-output"


class ManifestError(Exception):
    """One or more problems in the manifest. Holds every message found."""

    def __init__(self, errors: list[str]):
        super().__init__("\n".join(errors))
        self.errors = errors


@dataclass
class Component:
    """One merged component, before validation.

    `fields` holds what the files set. `origin` is the label of the last file
    that changed it. `base_dir` is the directory of the file that set `path`,
    because a path is relative to the file that declares it.
    """

    fields: dict[str, Any]
    origin: str
    base_dir: Path | None = None

    @property
    def path(self) -> Path:
        return (self.base_dir / self.fields["path"]).resolve()


# ── Section rules ────────────────────────────────────────────────────────────
#
# Each section has a check: it gets the component and its effective entry
# (envelope and fields already copied), adds the fields it derives, and
# returns its errors. Disabled components get the schema checks only, so a
# check skips filesystem work for them.

Check = Callable[[str, Component, dict, str], list[str]]


def _check_package(key: str, comp: Component, entry: dict, where: str) -> list[str]:
    return []


def _expand(template: str, version: str, arch: str) -> str:
    bad = set(TEMPLATE_RE.findall(template)) - {"version", "arch"}
    if bad:
        raise ValueError(f"unknown placeholders: {', '.join('{' + n + '}' for n in sorted(bad))}")
    out = template.replace("{version}", version).replace("{arch}", arch)
    if "{" in out or "}" in out:
        raise ValueError("unbalanced braces")
    return out


def _check_binary(key: str, comp: Component, entry: dict, where: str) -> list[str]:
    """Exact version, https URLs, and one download per arch in `artifacts`.

    The target arch is known only at build time, so every arch is expanded.
    The build replaces `artifacts` with `resolved` for the arch it built.
    """
    f = comp.fields
    errors: list[str] = []
    if not EXACT_VERSION_RE.match(f["version"]):
        errors.append(f"{where}.version: must be an exact version, got {f['version']!r}")
    arch_map = f.get("arch", {})
    if not isinstance(arch_map, dict) or not all(
        k in ARCHES and isinstance(v, str) for k, v in arch_map.items()
    ):
        errors.append(f"{where}.arch: must map {' / '.join(ARCHES)} to upstream names")
    for name in ("url", "checksum_url"):
        if not f[name].startswith("https://"):
            errors.append(f"{where}.{name}: must be an https:// URL")
    if errors:
        return errors

    artifacts = {}
    for arch in ARCHES:
        upstream = arch_map.get(arch, arch)
        try:
            url = _expand(f["url"], f["version"], upstream)
            checksum_url = _expand(f["checksum_url"], f["version"], upstream)
            extract = _expand(f["extract"], f["version"], upstream) if "extract" in f else None
        except ValueError as exc:
            return [f"{where}: {exc}"]
        file = Path(urlparse(url).path).name
        is_archive = file.endswith(ARCHIVE_SUFFIXES)
        if is_archive and not extract:
            return [f"{where}.extract: required, {file} is an archive"]
        if extract and not is_archive:
            return [f"{where}.extract: not allowed, {file} is not an archive"]
        artifacts[arch] = {"url": url, "checksum_url": checksum_url, "file": file}
        if extract:
            artifacts[arch]["extract"] = extract
    entry["artifacts"] = artifacts
    return []


def _check_provider(key: str, comp: Component, entry: dict, where: str) -> list[str]:
    errors = []
    if not PROVIDER_SOURCE_RE.match(comp.fields["source"]):
        errors.append(
            f"{where}.source: must be <namespace>/<type> on the public registry, "
            f"got {comp.fields['source']!r}"
        )
    if not comp.fields["version"].strip():
        errors.append(f"{where}.version: must not be empty")
    return errors


def _check_python_env(key: str, comp: Component, entry: dict, where: str) -> list[str]:
    path = comp.path
    # One name: the key names the env in the image (/opt/propeller/python/<key>)
    # and in py-run, which derives it from the env directory name.
    if path.name != key:
        return [f"{where}.path: directory name must equal the key ({path.name!r} != {key!r})"]
    if not entry["enabled"]:
        return []
    # .python-version is required: without it uv can pick the base image's
    # system Python (3.9 on AL2023), not the one the env was locked for.
    missing = [name for name in ENV_FILES if not (path / name).is_file()]
    if missing:
        return [f"{where}.path: {comp.fields['path']} has no {', '.join(missing)}"]
    entry["lock_sha256"] = _sha256(path / "uv.lock")
    return []


def _check_script(key: str, comp: Component, entry: dict, where: str) -> list[str]:
    if not entry["enabled"]:
        return []
    if not comp.path.is_file():
        return [f"{where}.path: {comp.fields['path']} is not a file"]
    entry["sha256"] = _sha256(comp.path)
    return []


@dataclass(frozen=True)
class Section:
    optional: frozenset[str]
    required: frozenset[str]
    check: Check

    @property
    def fields(self) -> frozenset[str]:
        return self.optional | self.required


# Sections, in install order. Within a section, components install in key order.
SECTIONS: dict[str, Section] = {
    "packages": Section(frozenset(), frozenset(), _check_package),
    "binaries": Section(
        frozenset({"arch", "extract", "check"}),
        frozenset({"version", "url", "checksum_url"}),
        _check_binary,
    ),
    "terraform_providers": Section(frozenset(), frozenset({"source", "version"}), _check_provider),
    "python_envs": Section(frozenset(), frozenset({"path"}), _check_python_env),
    "scripts": Section(frozenset(), frozenset({"path"}), _check_script),
}
# Sections whose components bring files into the build (staged by `stage`).
FILE_SECTIONS = ("python_envs", "scripts")

ENVELOPE = ("enabled", "required")
NON_STRING_FIELDS = {"arch"}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ── Load ─────────────────────────────────────────────────────────────────────


class _StrictLoader(yaml.SafeLoader):
    """SafeLoader that rejects duplicate keys (a duplicate would drop an entry)."""


def _construct_mapping(loader: yaml.SafeLoader, node: yaml.MappingNode) -> dict:
    seen: set[Any] = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                None, None, f"duplicate key {key!r}", key_node.start_mark
            )
        seen.add(key)
    return loader.construct_mapping(node)


_StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


@dataclass
class Layer:
    """One manifest file: the base manifest or the overrides."""

    label: str
    directory: Path
    doc: dict


def load_yaml(path: Path) -> Layer:
    try:
        doc = yaml.load(path.read_text(), Loader=_StrictLoader)  # noqa: S506 (strict SafeLoader)
    except OSError as exc:
        raise ManifestError([f"{path.name}: cannot read: {exc}"]) from exc
    except yaml.YAMLError as exc:
        raise ManifestError([f"{path.name}: invalid YAML: {exc}"]) from exc
    if not isinstance(doc, dict):
        raise ManifestError([f"{path.name}: must be a map"])

    errors: list[str] = []
    unknown = set(doc) - {"version", "base", *SECTIONS}
    if unknown:
        errors.append(
            f"{path.name}: unknown top-level keys: {', '.join(sorted(map(str, unknown)))} "
            f"(sections: {', '.join(SECTIONS)})"
        )
    if str(doc.get("version")) != SCHEMA_VERSION:
        errors.append(f'{path.name}: version must be "{SCHEMA_VERSION}"')
    for name in ("base", *SECTIONS):
        doc[name] = doc.get(name) or {}
        if not isinstance(doc[name], dict):
            errors.append(f"{path.name}: {name} must be a map keyed by name")
    if errors:
        raise ManifestError(errors)
    return Layer(path.name, path.parent, doc)


# ── Merge ────────────────────────────────────────────────────────────────────


def merge(layers: list[Layer]) -> tuple[str | None, dict[str, dict[str, Component]], list[str]]:
    """Merge layers by section and key. The first layer is the base manifest.

    One rule: an existing key gets its fields replaced one by one; a new key is
    added; a field set to null is removed. Only the base manifest may set
    `required`. An override cannot disable a key that does not exist (a typo
    would otherwise pass silently).
    """
    errors: list[str] = []
    base_image: str | None = None
    merged: dict[str, dict[str, Component]] = {name: {} for name in SECTIONS}

    for index, layer in enumerate(layers):
        is_base = index == 0
        base = layer.doc["base"]
        unknown = set(base) - {"image"}
        if unknown:
            errors.append(f"{layer.label}: base: unknown keys: {', '.join(sorted(unknown))}")
        if "image" in base:
            if isinstance(base["image"], str) and base["image"]:
                base_image = base["image"]
            else:
                errors.append(f"{layer.label}: base.image must be a non-empty string")

        for section in SECTIONS:
            for key, entry in layer.doc[section].items():
                where = f"{layer.label}: {section}.{key}"
                error = _merge_entry(merged[section], key, entry, layer, is_base)
                if error:
                    errors.append(f"{where}: {error}")

    if base_image is None:
        errors.append("base.image is required")
    return base_image, merged, errors


def _merge_entry(
    components: dict[str, Component], key: Any, entry: Any, layer: Layer, is_base: bool
) -> str | None:
    """Merge one entry into its section. Returns an error, or None."""
    if not isinstance(key, str) or not KEY_RE.match(key):
        return "invalid key (letters, digits, '.', '_', '+', '-')"
    if not isinstance(entry, dict):
        return "must be a map (use {} for no fields)"
    if not is_base and "required" in entry:
        return "`required` can only be set in the base manifest"

    comp = components.get(key)
    if comp is None:
        if not is_base and entry.get("enabled") is False:
            return "cannot disable, not in the base manifest"
        comp = components[key] = Component({}, layer.label)

    for field, value in entry.items():
        if value is None:
            comp.fields.pop(field, None)
        else:
            comp.fields[field] = value
    if entry.get("path") is not None:
        comp.base_dir = layer.directory
    comp.origin = layer.label
    return None


# ── Validate ─────────────────────────────────────────────────────────────────


def validate(merged: dict[str, dict[str, Component]]) -> tuple[dict[str, dict[str, dict]], list[str]]:
    """Check every component and return the effective entries by section."""
    errors: list[str] = []
    out: dict[str, dict[str, dict]] = {name: {} for name in SECTIONS}
    for name, section in SECTIONS.items():
        for key in sorted(merged[name]):
            where = f"{name}.{key}"
            entry, entry_errors = _validate_component(key, merged[name][key], section, where)
            errors += entry_errors
            if entry is not None:
                out[name][key] = entry
    errors += _check_duplicate_providers(out["terraform_providers"])
    return out, errors


def _validate_component(
    key: str, comp: Component, section: Section, where: str
) -> tuple[dict | None, list[str]]:
    """Schema checks, then the section's own check. Returns (entry, errors)."""
    f = comp.fields
    errors: list[str] = []
    unknown = set(f) - set(ENVELOPE) - section.fields
    if unknown:
        errors.append(f"{where}: unknown fields: {', '.join(sorted(unknown))}")
    missing = section.required - set(f)
    if missing:
        errors.append(f"{where}: missing fields: {', '.join(sorted(missing))}")
    errors += [f"{where}.{flag}: must be true or false"
               for flag in ENVELOPE if flag in f and not isinstance(f[flag], bool)]
    errors += [f'{where}.{field}: must be a string (quote versions, e.g. "1.30")'
               for field in sorted(section.fields - NON_STRING_FIELDS)
               if field in f and not isinstance(f[field], str)]
    if errors:
        return None, errors

    entry: dict[str, Any] = {"enabled": f.get("enabled", True), "required": f.get("required", False)}
    if entry["required"] and not entry["enabled"]:
        return None, [f"{where}: is required and cannot be disabled"]
    entry.update({field: f[field] for field in sorted(section.fields) if field in f})
    entry["origin"] = comp.origin
    return entry, section.check(key, comp, entry, where)


def _check_duplicate_providers(providers: dict[str, dict]) -> list[str]:
    seen: dict[tuple[str, str], str] = {}
    errors = []
    for key, entry in providers.items():
        if not entry["enabled"]:
            continue
        ident = (entry["source"], entry["version"].replace(" ", ""))
        if ident in seen:
            errors.append(
                f"terraform_providers.{key}: same source and version as terraform_providers.{seen[ident]}"
            )
        seen.setdefault(ident, key)
    return errors


# ── Render and stage ─────────────────────────────────────────────────────────


def render(manifest: Path, overrides: Path | None) -> tuple[dict, dict[str, dict[str, Path]]]:
    """Return (effective manifest, files to stage). Raises ManifestError.

    The files are the absolute sources of the enabled python envs and scripts,
    by section and key. They stay out of the manifest, which is the same on
    every machine.
    """
    layers = [load_yaml(manifest)]
    if overrides is not None:
        layers.append(load_yaml(overrides))

    base_image, merged, errors = merge(layers)
    sections, validation_errors = validate(merged)
    errors += validation_errors
    if errors:
        raise ManifestError(errors)

    effective: dict[str, Any] = {
        "version": SCHEMA_VERSION,
        "base": {"image": base_image},
        "sources": [layer.label for layer in layers],
        **sections,
    }
    files = {
        name: {key: merged[name][key].path for key, entry in sections[name].items() if entry["enabled"]}
        for name in FILE_SECTIONS
    }
    return effective, files


def stage(effective: dict, files: dict[str, dict[str, Path]], out: Path) -> None:
    """Write the build input: out/image.json, out/python/<key>/, out/scripts/<key>."""
    if out.exists():
        if not (out / OUTPUT_MARKER).is_file():
            raise ManifestError([f"{out}: exists and was not created by the renderer; refusing to delete it"])
        shutil.rmtree(out)
    (out / "python").mkdir(parents=True)
    (out / "scripts").mkdir()
    (out / OUTPUT_MARKER).write_text("")

    for key, src in files["python_envs"].items():
        (out / "python" / key).mkdir()
        for name in ENV_FILES:
            shutil.copy2(src / name, out / "python" / key / name)
    for key, src in files["scripts"].items():
        shutil.copy2(src, out / "scripts" / key)
        (out / "scripts" / key).chmod(0o755)

    (out / "image.json").write_text(json.dumps(effective, indent=2, sort_keys=True) + "\n")


# ── Summary and diff ─────────────────────────────────────────────────────────

# Fields a diff compares, besides `resolved`. Origin and derived fields
# (artifacts) are left out: they describe where a value came from.
DIFF_FIELDS = ("version", "source", "url", "checksum_url", "extract", "check",
               "arch", "path", "lock_sha256", "sha256")


def _detail(section: str, entry: dict) -> str:
    if section == "terraform_providers":
        return f"{entry['source']} {entry['version']}"
    if section in FILE_SECTIONS:
        return entry["path"]
    return entry.get("version", "")


def summary(effective: dict) -> str:
    rows = [("SECTION", "NAME", "VERSION / PATH", "STATE", "ORIGIN")]
    for section in SECTIONS:
        for key, entry in effective[section].items():
            state = "required" if entry["required"] else ("enabled" if entry["enabled"] else "disabled")
            rows.append((section, key, _detail(section, entry), state, entry["origin"]))
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    lines = [f"base: {effective['base']['image']}", ""]
    lines += ["  ".join(cell.ljust(w) for cell, w in zip(row, widths)).rstrip() for row in rows]
    return "\n".join(lines)


def _resolved_lines(name: str, old: dict, new: dict) -> list[str]:
    """Changes in `resolved`. Compared only when both sides were built: a
    rendered manifest has no `resolved`, because nothing is built yet."""
    if "resolved" not in old or "resolved" not in new:
        return []
    return [
        f"~ {name}.resolved.{field}: {old['resolved'].get(field)} -> {new['resolved'].get(field)}"
        for field in sorted(set(old["resolved"]) | set(new["resolved"]))
        if old["resolved"].get(field) != new["resolved"].get(field)
    ]


def diff(previous: dict | None, current: dict) -> list[str]:
    """Return plan-style lines: + added, - removed, ~ changed."""
    if previous is None:
        return ["(no previously applied manifest: every enabled component is new)"]
    lines = []
    old_base, new_base = previous.get("base", {}), current["base"]
    if old_base.get("image") != new_base["image"]:
        lines.append(f"~ base.image: {old_base.get('image')} -> {new_base['image']}")
    lines += _resolved_lines("base", old_base, new_base)

    for section in SECTIONS:
        old = {k: v for k, v in previous.get(section, {}).items() if v.get("enabled", True)}
        new = {k: v for k, v in current.get(section, {}).items() if v.get("enabled", True)}
        for key in sorted(old.keys() | new.keys()):
            name = f"{section}.{key}"
            if key not in old or key not in new:
                sign, entry = ("+", new[key]) if key not in old else ("-", old[key])
                detail = _detail(section, entry)
                lines.append(f"{sign} {name}" + (f" ({detail})" if detail else ""))
                continue
            lines += [
                f"~ {name}.{field}: {old[key].get(field)} -> {new[key].get(field)}"
                for field in DIFF_FIELDS
                if old[key].get(field) != new[key].get(field)
            ]
            lines += _resolved_lines(name, old[key], new[key])
    return lines or ["No changes."]


# ── CLI ──────────────────────────────────────────────────────────────────────


def _parse_args(argv: list[str]) -> argparse.Namespace:
    project_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", type=Path, default=project_dir / "image.yaml",
                        help="base manifest (default: image.yaml next to renderer/)")
    parser.add_argument("--overrides", type=Path, default=None,
                        help="overrides file (default: image.overrides.yaml next to the manifest, if present)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("show", help="print the effective manifest as JSON")
    stage_cmd = sub.add_parser("stage", help="write the build input and print a summary")
    stage_cmd.add_argument("--out", type=Path, required=True, help="output directory")
    stage_cmd.add_argument("--previous", type=Path, default=None,
                           help="previously applied image.json, to print a diff")
    diff_cmd = sub.add_parser("diff", help="diff two built manifests (image.json files)")
    diff_cmd.add_argument("previous", type=Path, help="older image.json (may be absent)")
    diff_cmd.add_argument("current", type=Path, help="newer image.json")
    return parser.parse_args(argv)


def _read_json(path: Path | None) -> dict | None:
    if path is None or not path.is_file():
        return None
    return json.loads(path.read_text())


def _print_diff(previous: dict | None, current: dict) -> None:
    for line in diff(previous, current):
        print(f"  {line}")


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    if args.command == "diff":
        _print_diff(_read_json(args.previous), json.loads(args.current.read_text()))
        return 0

    overrides = args.overrides
    if overrides is None:
        candidate = args.manifest.parent / "image.overrides.yaml"
        overrides = candidate if candidate.is_file() else None

    try:
        effective, files = render(args.manifest, overrides)
        if args.command == "show":
            print(json.dumps(effective, indent=2, sort_keys=True))
            return 0
        stage(effective, files, args.out)
    except ManifestError as exc:
        for message in exc.errors:
            print(f"error: {message}", file=sys.stderr)
        return 1

    print(summary(effective))
    if args.previous is not None:
        print("\nChanges against the last applied manifest:")
        _print_diff(_read_json(args.previous), effective)
    return 0


if __name__ == "__main__":
    sys.exit(main())
