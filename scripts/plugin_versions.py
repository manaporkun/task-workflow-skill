#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
MARKETPLACE_PATH = ROOT / ".claude-plugin" / "marketplace.json"
RELEASE_PLEASE_CONFIG_PATH = ROOT / "release-please-config.json"
RELEASE_PLEASE_MANIFEST_PATH = ROOT / ".release-please-manifest.json"
PLUGIN_MANIFEST_SUFFIX = Path(".claude-plugin") / "plugin.json"
SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        fail(f"{path.relative_to(ROOT)} not found")
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)} is invalid JSON: {exc}")


def dump_json(data: Any) -> str:
    return json.dumps(data, indent=2) + "\n"


def parse_semver(version: str) -> tuple[int, int, int]:
    match = SEMVER_RE.fullmatch(version)
    if not match:
        fail(f"Unsupported version '{version}'. Expected MAJOR.MINOR.PATCH")
    return tuple(int(part) for part in match.groups())


def bump_semver(version: str, release_type: str) -> str:
    major, minor, patch = parse_semver(version)
    if release_type == "major":
        return f"{major + 1}.0.0"
    if release_type == "minor":
        return f"{major}.{minor + 1}.0"
    if release_type == "patch":
        return f"{major}.{minor}.{patch + 1}"
    fail(f"Unsupported release type '{release_type}'")


def discover_plugins() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    marketplace = load_json(MARKETPLACE_PATH)
    discovered_manifests: dict[str, tuple[Path, dict[str, Any]]] = {}

    for plugin_manifest_path in sorted(ROOT.glob("plugins/*/.claude-plugin/plugin.json")):
        plugin_dir = plugin_manifest_path.parent.parent
        relative_plugin_dir = str(plugin_dir.relative_to(ROOT))
        discovered_manifests[relative_plugin_dir] = (
            plugin_manifest_path,
            load_json(plugin_manifest_path),
        )

    plugins = []

    for index, entry in enumerate(marketplace.get("plugins", [])):
        name = entry.get("name")
        source = entry.get("source")
        if not name:
            fail(f"Marketplace plugin at index {index} is missing a name")
        if not source or not source.startswith("./plugins/"):
            fail(f"Marketplace plugin '{name}' must use a ./plugins/... source path")

        plugin_path = source.removeprefix("./")
        if plugin_path not in discovered_manifests:
            fail(f"Marketplace plugin '{name}' points to missing directory '{plugin_path}'")

        plugin_dir = ROOT / plugin_path
        plugin_manifest_path, plugin_manifest = discovered_manifests[plugin_path]
        plugin_manifest_name = plugin_manifest.get("name")

        if plugin_manifest_name != name:
            fail(
                f"Marketplace plugin '{name}' does not match "
                f"{plugin_manifest_path.relative_to(ROOT)} name '{plugin_manifest_name}'"
            )

        plugin_record = {
            "index": index,
            "name": name,
            "source": source,
            "path": str(plugin_dir.relative_to(ROOT)),
            "entry": entry,
            "manifest": plugin_manifest,
            "manifest_path": plugin_manifest_path,
        }
        plugins.append(plugin_record)

    marketplace_paths = {plugin["path"] for plugin in plugins}
    undiscovered = sorted(set(discovered_manifests) - marketplace_paths)
    if undiscovered:
        fail(
            "These plugin manifests are missing from .claude-plugin/marketplace.json: "
            + ", ".join(undiscovered)
        )

    return marketplace, plugins


def generated_release_please_config(marketplace: dict[str, Any], plugins: list[dict[str, Any]]) -> dict[str, Any]:
    packages: dict[str, Any] = {
        ".": {
            "release-type": "simple",
            "bump-minor-pre-major": True,
            "changelog-path": "CHANGELOG.md",
            "extra-files": [
                {
                    "type": "json",
                    "path": ".claude-plugin/marketplace.json",
                    "jsonpath": "$.version",
                }
            ],
        }
    }

    for plugin in plugins:
        package_path = Path(plugin["path"])
        root_relative_from_package = Path(*([".."] * len(package_path.parts))) if package_path.parts else Path(".")
        packages[plugin["path"]] = {
            "release-type": "simple",
            "bump-minor-pre-major": True,
            "component": plugin["name"],
            "changelog-path": "CHANGELOG.md",
            "extra-files": [
                {
                    "type": "json",
                    "path": ".claude-plugin/plugin.json",
                    "jsonpath": "$.version",
                },
                {
                    "type": "json",
                    "path": str(root_relative_from_package / ".claude-plugin" / "marketplace.json"),
                    "jsonpath": f"$.plugins[{plugin['index']}].version",
                },
            ],
        }

    return {"packages": packages}


def generated_release_please_manifest(marketplace: dict[str, Any], plugins: list[dict[str, Any]]) -> dict[str, str]:
    manifest: dict[str, str] = {"." : marketplace["version"]}
    for plugin in plugins:
        manifest[plugin["path"]] = plugin["manifest"]["version"]
    return manifest


def sync_marketplace_versions(marketplace: dict[str, Any], plugins: list[dict[str, Any]]) -> dict[str, Any]:
    updated = json.loads(json.dumps(marketplace))
    plugins_by_name = {plugin["name"]: plugin for plugin in plugins}

    for entry in updated.get("plugins", []):
        plugin = plugins_by_name.get(entry.get("name"))
        if plugin is None:
            fail(f"Marketplace plugin '{entry.get('name')}' has no matching plugin manifest")
        entry["version"] = plugin["manifest"]["version"]

    return updated


def write_or_check(path: Path, content: str, write: bool) -> bool:
    current = path.read_text() if path.exists() else None
    changed = current != content
    if changed and write:
        path.write_text(content)
        print(f"Updated {path.relative_to(ROOT)}")
    return changed


def sync_generated_files(write: bool) -> int:
    marketplace, plugins = discover_plugins()

    updated_marketplace = sync_marketplace_versions(marketplace, plugins)
    config = generated_release_please_config(updated_marketplace, plugins)
    manifest = generated_release_please_manifest(updated_marketplace, plugins)

    changed = False
    changed |= write_or_check(MARKETPLACE_PATH, dump_json(updated_marketplace), write)
    changed |= write_or_check(RELEASE_PLEASE_CONFIG_PATH, dump_json(config), write)
    changed |= write_or_check(RELEASE_PLEASE_MANIFEST_PATH, dump_json(manifest), write)

    if not write:
        if changed:
            print("Generated files are out of date")
            return 1
        print("Generated files are in sync")
    return 0


def detect_changed_plugins(base: str, head: str) -> list[str]:
    try:
        output = subprocess.check_output(
            ["git", "diff", "--name-only", f"{base}...{head}"],
            cwd=ROOT,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        fail(f"git diff failed: {exc}")

    changed = set()
    for line in output.splitlines():
        parts = Path(line).parts
        if len(parts) >= 2 and parts[0] == "plugins":
            changed.add(parts[1])
    return sorted(changed)


def cmd_sync(args: argparse.Namespace) -> int:
    return sync_generated_files(write=args.write)


def cmd_changed(args: argparse.Namespace) -> int:
    changed = detect_changed_plugins(args.base, args.head)
    for plugin in changed:
        print(plugin)
    return 0


def cmd_bump(args: argparse.Namespace) -> int:
    _, plugins = discover_plugins()
    plugin = next((item for item in plugins if item["name"] == args.plugin), None)
    if plugin is None:
        fail(f"Unknown plugin '{args.plugin}'")

    manifest = plugin["manifest"]
    current_version = manifest["version"]
    next_version = (
        bump_semver(current_version, args.bump)
        if args.bump in {"major", "minor", "patch"}
        else args.bump
    )
    parse_semver(next_version)
    manifest["version"] = next_version

    plugin["manifest_path"].write_text(dump_json(manifest))
    print(
        f"Updated {plugin['manifest_path'].relative_to(ROOT)} "
        f"from {current_version} to {next_version}"
    )

    return sync_generated_files(write=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Manage marketplace and Release Please versions for all plugins."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    sync_parser = subparsers.add_parser(
        "sync-all",
        help="Sync marketplace versions plus generated Release Please config and manifest.",
    )
    sync_parser.add_argument("--write", action="store_true", help="Write changes to disk.")
    sync_parser.set_defaults(func=cmd_sync)

    changed_parser = subparsers.add_parser(
        "changed",
        help="Print plugin names changed between two git refs.",
    )
    changed_parser.add_argument("--base", default="origin/main", help="Base git ref.")
    changed_parser.add_argument("--head", default="HEAD", help="Head git ref.")
    changed_parser.set_defaults(func=cmd_changed)

    bump_parser = subparsers.add_parser(
        "bump",
        help="Manually bump one plugin version and sync generated files.",
    )
    bump_parser.add_argument("plugin", help="Plugin name, for example 'task'.")
    bump_parser.add_argument(
        "bump",
        help="Version bump type (major|minor|patch) or an explicit semver like 2.3.4.",
    )
    bump_parser.set_defaults(func=cmd_bump)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
