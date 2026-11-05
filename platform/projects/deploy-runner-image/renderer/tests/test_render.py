"""Unit tests for the image manifest renderer."""

from __future__ import annotations

import json
import sys
import textwrap
from pathlib import Path

import pytest

RENDERER_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RENDERER_DIR))

import render  # noqa: E402

FRAMEWORK_MANIFEST = RENDERER_DIR.parent / "image.yaml"

BASE = """\
version: "1"
base:
  image: example/base:1
packages:
  jq: { required: true }
  git: {}
binaries:
  tool:
    version: "1.2.3"
    url: https://example.com/{version}/tool-{arch}.tar.gz
    checksum_url: https://example.com/{version}/SHA256SUMS
    arch: { amd64: x86_64 }
    extract: tool-{arch}/tool
terraform_providers:
  aws:
    source: hashicorp/aws
    version: "~> 6.49.0"
"""


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text))
    return path


def make_env(directory: Path) -> Path:
    write(directory / "pyproject.toml", '[project]\nname = "x"\nversion = "0"\n')
    write(directory / "uv.lock", "version = 1\n")
    write(directory / ".python-version", "3.14\n")
    return directory


def render_files(tmp_path: Path, overrides: str | None = None, base: str = BASE):
    manifest = write(tmp_path / "image.yaml", base)
    over = write(tmp_path / "image.overrides.yaml", overrides) if overrides else None
    return render.render(manifest, over)


def errors_of(tmp_path: Path, overrides: str | None = None, base: str = BASE) -> str:
    with pytest.raises(render.ManifestError) as exc:
        render_files(tmp_path, overrides, base)
    return "\n".join(exc.value.errors)


def over(body: str) -> str:
    return 'version: "1"\n' + textwrap.dedent(body)


# ── Framework manifest ───────────────────────────────────────────────────────


def test_framework_manifest_renders():
    effective, _ = render.render(FRAMEWORK_MANIFEST, None)
    for section, key in (("binaries", "terraform"), ("binaries", "just"), ("binaries", "uv"),
                         ("packages", "jq"), ("terraform_providers", "aws")):
        assert effective[section][key]["required"] is True, key
    assert effective["sources"] == ["image.yaml"]
    # helm is both a binary and a provider: sections keep the names apart.
    assert "helm" in effective["binaries"] and "helm" in effective["terraform_providers"]


def test_effective_manifest_is_sectioned(tmp_path):
    effective, _ = render_files(tmp_path)
    assert set(effective) == {"version", "base", "sources", *render.SECTIONS}
    assert effective["packages"]["git"] == {"enabled": True, "required": False, "origin": "image.yaml"}


# ── Merge ────────────────────────────────────────────────────────────────────


def test_overrides_change_disable_and_add_by_key(tmp_path):
    effective, _ = render_files(tmp_path, over("""\
        binaries:
          tool:
            version: "1.2.4"
        packages:
          git:
            enabled: false
          postgresql16: {}
    """))
    assert effective["binaries"]["tool"]["version"] == "1.2.4"
    assert effective["binaries"]["tool"]["artifacts"]["amd64"]["url"] == "https://example.com/1.2.4/tool-x86_64.tar.gz"
    assert effective["binaries"]["tool"]["origin"] == "image.overrides.yaml"
    assert effective["packages"]["git"]["enabled"] is False
    assert effective["packages"]["postgresql16"]["origin"] == "image.overrides.yaml"
    assert effective["packages"]["jq"]["origin"] == "image.yaml"


def test_overrides_can_change_base_image(tmp_path):
    effective, _ = render_files(tmp_path, over("base:\n  image: other/base:2\n"))
    assert effective["base"]["image"] == "other/base:2"


def test_disabling_an_unknown_key_is_rejected(tmp_path):
    out = errors_of(tmp_path, over("packages:\n  gti:\n    enabled: false\n"))
    assert "packages.gti: cannot disable, not in the base manifest" in out


def test_null_or_scalar_entry_is_rejected(tmp_path):
    assert "must be a map (use {} for no fields)" in errors_of(tmp_path, over("packages:\n  curl:\n"))
    assert "must be a map" in errors_of(tmp_path, over("binaries:\n  uv: 0.10.9\n"))


def test_unknown_section_and_kind_field_are_rejected(tmp_path):
    assert "unknown top-level keys: components" in errors_of(
        tmp_path, over("components:\n  git:\n    kind: package\n")
    )
    assert "packages.git: unknown fields: kind" in errors_of(
        tmp_path, over("packages:\n  git:\n    kind: package\n")
    )


def test_duplicate_key_is_rejected(tmp_path):
    assert "duplicate key 'git'" in errors_of(tmp_path, base=BASE.replace("  git: {}\n", "  git: {}\n  git: {}\n"))


def test_required_is_base_only_and_cannot_be_disabled(tmp_path):
    assert "can only be set in the base manifest" in errors_of(
        tmp_path, over("packages:\n  git:\n    required: true\n")
    )
    assert "packages.jq: is required and cannot be disabled" in errors_of(
        tmp_path, over("packages:\n  jq:\n    enabled: false\n")
    )


def test_all_errors_are_reported_at_once(tmp_path):
    out = errors_of(tmp_path, over("""\
        packages:
          jq:
            enabled: false
        binaries:
          tool:
            version: "~> 1"
    """))
    assert "jq: is required" in out
    assert "must be an exact version" in out


def test_null_removes_an_inherited_field(tmp_path):
    effective, _ = render_files(tmp_path, over("""\
        binaries:
          tool:
            url: https://example.com/{version}/tool-{arch}
            extract: null
            arch: null
    """))
    tool = effective["binaries"]["tool"]
    assert "extract" not in tool and "arch" not in tool
    assert tool["artifacts"]["amd64"] == {
        "url": "https://example.com/1.2.3/tool-amd64",
        "checksum_url": "https://example.com/1.2.3/SHA256SUMS",
        "file": "tool-amd64",
    }


def test_null_cannot_remove_a_required_field(tmp_path):
    assert "binaries.tool: missing fields: version" in errors_of(
        tmp_path, over("binaries:\n  tool:\n    version: null\n")
    )


# ── Binaries and providers ───────────────────────────────────────────────────


def test_unquoted_float_version_is_rejected(tmp_path):
    assert "must be a string (quote versions" in errors_of(
        tmp_path, over("binaries:\n  tool:\n    version: 1.30\n")
    )


def test_binary_needs_exact_version_but_provider_accepts_constraints(tmp_path):
    assert "must be an exact version" in errors_of(tmp_path, over('binaries:\n  tool:\n    version: "~> 1.2"\n'))
    effective, _ = render_files(tmp_path, over('terraform_providers:\n  aws:\n    version: ">= 6.0, < 7.0"\n'))
    assert effective["terraform_providers"]["aws"]["version"] == ">= 6.0, < 7.0"


def test_binary_artifacts_expand_per_arch(tmp_path):
    effective, _ = render_files(tmp_path)
    artifacts = effective["binaries"]["tool"]["artifacts"]
    assert artifacts["amd64"] == {
        "url": "https://example.com/1.2.3/tool-x86_64.tar.gz",
        "checksum_url": "https://example.com/1.2.3/SHA256SUMS",
        "file": "tool-x86_64.tar.gz",
        "extract": "tool-x86_64/tool",
    }
    assert artifacts["arm64"]["file"] == "tool-arm64.tar.gz"


def test_archive_needs_extract_and_raw_file_rejects_it(tmp_path):
    assert "extract: required" in errors_of(tmp_path, base=BASE.replace("    extract: tool-{arch}/tool\n", ""))
    assert "extract: not allowed" in errors_of(tmp_path, base=BASE.replace("tool-{arch}.tar.gz", "tool-{arch}"))


def test_unknown_placeholder_and_plain_http_are_rejected(tmp_path):
    assert "unknown placeholders: {os}" in errors_of(
        tmp_path, base=BASE.replace("tool-{arch}.tar.gz", "tool-{os}-{arch}.tar.gz")
    )
    assert "must be an https:// URL" in errors_of(
        tmp_path, base=BASE.replace("url: https://example.com/{version}/tool", "url: http://example.com/{version}/tool")
    )


def test_binary_check_must_be_a_string(tmp_path):
    effective, _ = render_files(tmp_path, over("binaries:\n  tool:\n    check: tool --version\n"))
    assert effective["binaries"]["tool"]["check"] == "tool --version"
    assert "binaries.tool.check: must be a string" in errors_of(
        tmp_path, over("binaries:\n  tool:\n    check: [tool, --version]\n")
    )


def test_duplicate_provider_source_and_version_is_rejected(tmp_path):
    out = errors_of(tmp_path, over("""\
        terraform_providers:
          aws-again:
            source: hashicorp/aws
            version: "~>6.49.0"
    """))
    assert "same source and version as terraform_providers.aws" in out


def test_provider_source_with_registry_host_is_rejected(tmp_path):
    out = errors_of(tmp_path, over("""\
        terraform_providers:
          thing:
            source: registry.example.com/acme/thing
            version: "1.0.0"
    """))
    assert "on the public registry" in out


def test_unknown_fields_are_rejected(tmp_path):
    assert "packages.git: unknown fields: version" in errors_of(
        tmp_path, over('packages:\n  git:\n    version: "2"\n')
    )


# ── Paths: python envs and scripts ───────────────────────────────────────────


def test_python_env_resolves_relative_to_declaring_file(tmp_path):
    make_env(tmp_path / "consumer" / "python" / "tools")
    write(tmp_path / "consumer" / "image.overrides.yaml", over("python_envs:\n  tools:\n    path: python/tools\n"))
    manifest = write(tmp_path / "framework" / "image.yaml", BASE)
    effective, files = render.render(manifest, tmp_path / "consumer" / "image.overrides.yaml")
    entry = effective["python_envs"]["tools"]
    assert entry["path"] == "python/tools"
    assert len(entry["lock_sha256"]) == 64
    assert files["python_envs"]["tools"] == (tmp_path / "consumer" / "python" / "tools").resolve()


def test_python_env_key_must_match_directory_name(tmp_path):
    make_env(tmp_path / "python" / "tools")
    assert "directory name must equal the key" in errors_of(
        tmp_path, over("python_envs:\n  other:\n    path: python/tools\n")
    )


def test_python_env_needs_lock_and_python_version(tmp_path):
    env = make_env(tmp_path / "python" / "tools")
    (env / "uv.lock").unlink()
    (env / ".python-version").unlink()
    out = errors_of(tmp_path, over("python_envs:\n  tools:\n    path: python/tools\n"))
    assert "has no uv.lock, .python-version" in out


def test_disabled_components_skip_filesystem_checks(tmp_path):
    effective, _ = render_files(tmp_path, base=BASE + "python_envs:\n  tools:\n    path: python/tools\n    enabled: false\n")
    assert effective["python_envs"]["tools"]["enabled"] is False


def test_missing_script_is_rejected(tmp_path):
    assert "ca.sh is not a file" in errors_of(tmp_path, over("scripts:\n  ca:\n    path: ca.sh\n"))


# ── Stage, summary, diff ─────────────────────────────────────────────────────


def test_stage_writes_build_input(tmp_path):
    make_env(tmp_path / "python" / "tools")
    write(tmp_path / "ca.sh", "#!/bin/sh\n")
    effective, files = render_files(tmp_path, over("""\
        python_envs:
          tools:
            path: python/tools
        scripts:
          ca:
            path: ca.sh
    """))
    out = tmp_path / ".build"
    render.stage(effective, files, out)
    assert json.loads((out / "image.json").read_text()) == effective
    assert (out / "python" / "tools" / ".python-version").is_file()
    assert (out / "scripts" / "ca").stat().st_mode & 0o111
    render.stage(effective, files, out)  # re-staging replaces its own output


def test_stage_with_no_envs_or_scripts_writes_empty_dirs(tmp_path):
    effective, files = render_files(tmp_path)
    out = tmp_path / ".build"
    render.stage(effective, files, out)
    assert list((out / "python").iterdir()) == []
    assert list((out / "scripts").iterdir()) == []


def test_stage_refuses_to_delete_a_foreign_directory(tmp_path):
    effective, files = render_files(tmp_path)
    foreign = tmp_path / "keep-me"
    write(foreign / "important.txt", "data")
    with pytest.raises(render.ManifestError, match="refusing to delete"):
        render.stage(effective, files, foreign)
    assert (foreign / "important.txt").is_file()


def test_summary_lists_every_component_once(tmp_path):
    effective, _ = render_files(tmp_path, over("packages:\n  git:\n    enabled: false\n"))
    text = render.summary(effective)
    assert "base: example/base:1" in text
    assert sum(1 for line in text.splitlines() if line.split()[:2] == ["packages", "git"]) == 1
    assert "disabled" in text and "required" in text


def test_diff_reports_added_removed_changed(tmp_path):
    previous, _ = render_files(tmp_path)
    current, _ = render_files(tmp_path, over("""\
        binaries:
          tool:
            version: "1.2.4"
        packages:
          git:
            enabled: false
          curl: {}
    """))
    lines = render.diff(previous, current)
    assert "+ packages.curl" in lines
    assert "- packages.git" in lines
    assert "~ binaries.tool.version: 1.2.3 -> 1.2.4" in lines
    assert render.diff(current, current) == ["No changes."]
    assert "no previously applied manifest" in render.diff(None, current)[0]


def built(effective: dict, **resolved) -> dict:
    """A copy of a rendered manifest with `resolved` objects, as the build writes."""
    doc = json.loads(json.dumps(effective))
    doc["base"]["resolved"] = {"digest": resolved.get("digest", "sha256:aaa")}
    doc["packages"]["jq"]["resolved"] = {"version": resolved.get("jq", "1.7-1")}
    doc["terraform_providers"]["aws"]["resolved"] = {"version": resolved.get("aws", "6.49.0")}
    return doc


def test_plan_diff_ignores_resolved_and_apply_diff_shows_it(tmp_path):
    rendered, _ = render_files(tmp_path)
    stored = built(rendered)
    rebuilt = built(rendered, digest="sha256:bbb", jq="1.8-1", aws="6.49.5")
    # plan: stored (built) manifest against a fresh render.
    assert render.diff(stored, rendered) == ["No changes."]
    # apply: stored manifest against the newly built one.
    assert render.diff(stored, rebuilt) == [
        "~ base.resolved.digest: sha256:aaa -> sha256:bbb",
        "~ packages.jq.resolved.version: 1.7-1 -> 1.8-1",
        "~ terraform_providers.aws.resolved.version: 6.49.0 -> 6.49.5",
    ]


def test_cli_diff_handles_a_missing_previous(tmp_path, capsys):
    current = write(tmp_path / "new.json", json.dumps(render_files(tmp_path)[0]))
    assert render.main(["diff", str(tmp_path / "absent.json"), str(current)]) == 0
    assert "no previously applied manifest" in capsys.readouterr().out


def test_cli_reports_errors_and_exits_1(tmp_path, capsys):
    manifest = write(tmp_path / "image.yaml", BASE.replace('version: "1"', 'version: "2"'))
    assert render.main(["--manifest", str(manifest), "show"]) == 1
    assert 'error: image.yaml: version must be "1"' in capsys.readouterr().err
