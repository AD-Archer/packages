#!/usr/bin/env python3
import argparse
import json
import os
import plistlib
import re
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timezone


DEFAULT_REQUIRED_ENTITLEMENTS = {
    "com.app.developer.team-identifier",
    "application-identifier",
}


def fetch_json(url: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "ad-archer-altstore-source-generator",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_file(url: str, dest_path: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "ad-archer-altstore-source-generator"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(dest_path, "wb") as f:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)


def extract_plist_from_mobileprovision(content: bytes) -> dict:
    start = content.find(b"<?xml")
    end = content.rfind(b"</plist>")
    if start == -1 or end == -1:
        return {}
    end += len(b"</plist>")
    raw = content[start:end]
    try:
        return plistlib.loads(raw)
    except Exception:
        return {}


def load_info_and_permissions(ipa_path: str) -> dict:
    with zipfile.ZipFile(ipa_path) as zf:
        members = zf.namelist()

        info_member = next((m for m in members if re.match(r"^Payload/[^/]+\.app/Info\.plist$", m)), None)
        if not info_member:
            raise RuntimeError("Info.plist not found in IPA")

        info_plist = plistlib.loads(zf.read(info_member))

        privacy = {}
        for key, value in info_plist.items():
            if key.endswith("UsageDescription") and isinstance(value, str):
                privacy[key] = value

        entitlements = []

        xcent_member = next(
            (
                m
                for m in members
                if re.match(r"^Payload/[^/]+\.app/(archived-expanded-entitlements\.xcent|[^/]+\.xcent)$", m)
            ),
            None,
        )
        if xcent_member:
            try:
                xcent = plistlib.loads(zf.read(xcent_member))
                entitlements = sorted(
                    [
                        key
                        for key in xcent.keys()
                        if key not in DEFAULT_REQUIRED_ENTITLEMENTS
                    ]
                )
            except Exception:
                entitlements = []

        if not entitlements:
            mobileprov_member = next(
                (m for m in members if re.match(r"^Payload/[^/]+\.app/embedded\.mobileprovision$", m)),
                None,
            )
            if mobileprov_member:
                mobileprov = extract_plist_from_mobileprovision(zf.read(mobileprov_member))
                ent = mobileprov.get("Entitlements", {})
                if isinstance(ent, dict):
                    entitlements = sorted(
                        [key for key in ent.keys() if key not in DEFAULT_REQUIRED_ENTITLEMENTS]
                    )

        return {
            "bundleIdentifier": info_plist.get("CFBundleIdentifier"),
            "version": str(info_plist.get("CFBundleShortVersionString", "")),
            "buildVersion": str(info_plist.get("CFBundleVersion", "")),
            "minOSVersion": str(info_plist.get("MinimumOSVersion", "")),
            "privacy": privacy,
            "entitlements": entitlements,
        }


def normalize_date(release_obj: dict) -> str:
    raw = release_obj.get("published_at") or release_obj.get("created_at")
    if raw:
        return raw
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def choose_asset(release_obj: dict, pattern: str) -> dict:
    rx = re.compile(pattern)
    for asset in release_obj.get("assets", []):
        name = asset.get("name", "")
        if rx.search(name):
            return asset
    raise RuntimeError(f"No release asset matched pattern: {pattern}")


def read_json_file(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json_file(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def build_source(config: dict, existing: dict, release_obj: dict, ipa_meta: dict, asset: dict) -> dict:
    source_cfg = config.get("source", {})
    app_cfg = config.get("app", {})
    bundle_id = app_cfg.get("bundleIdentifier") or ipa_meta.get("bundleIdentifier")
    if not bundle_id:
        raise RuntimeError("bundleIdentifier missing in both config and IPA metadata")

    existing_apps = existing.get("apps", []) if isinstance(existing.get("apps", []), list) else []
    existing_app = next(
        (a for a in existing_apps if a.get("bundleIdentifier") == bundle_id),
        {},
    )
    existing_versions = existing_app.get("versions", []) if isinstance(existing_app.get("versions", []), list) else []

    new_version = {
        "version": ipa_meta.get("version") or app_cfg.get("version"),
        "buildVersion": ipa_meta.get("buildVersion") or app_cfg.get("buildVersion"),
        "date": normalize_date(release_obj),
        "localizedDescription": release_obj.get("body") or f"Release {release_obj.get('tag_name', '')}".strip(),
        "downloadURL": asset.get("browser_download_url"),
        "size": int(asset.get("size", 0)),
    }

    min_os_version = ipa_meta.get("minOSVersion") or app_cfg.get("minOSVersion")
    if min_os_version:
        new_version["minOSVersion"] = min_os_version

    def version_id(v: dict) -> str:
        return f"{v.get('version', '')}::{v.get('buildVersion', '')}"

    new_id = version_id(new_version)
    deduped = [v for v in existing_versions if version_id(v) != new_id]
    versions = [new_version] + deduped

    app = {
        "name": app_cfg.get("name", "RustySound"),
        "bundleIdentifier": bundle_id,
        "developerName": app_cfg.get("developerName", "RustySound"),
        "subtitle": app_cfg.get("subtitle", ""),
        "localizedDescription": app_cfg.get("localizedDescription", ""),
        "iconURL": app_cfg.get("iconURL", source_cfg.get("iconURL", "")),
        "tintColor": app_cfg.get("tintColor", source_cfg.get("tintColor", "")),
        "category": app_cfg.get("category", "other"),
        "versions": versions,
        "appPermissions": {
            "entitlements": ipa_meta.get("entitlements", []),
            "privacy": ipa_meta.get("privacy", {}),
        },
    }

    screenshots = app_cfg.get("screenshots")
    if screenshots:
        app["screenshots"] = screenshots

    if "patreon" in app_cfg:
        app["patreon"] = app_cfg["patreon"]

    merged_apps = []
    replaced = False
    for candidate in existing_apps:
        if candidate.get("bundleIdentifier") == bundle_id:
            merged_apps.append(app)
            replaced = True
        else:
            merged_apps.append(candidate)
    if not replaced:
        merged_apps.append(app)

    existing_featured = existing.get("featuredApps", []) if isinstance(existing.get("featuredApps", []), list) else []
    featured = source_cfg.get("featuredApps", existing_featured)
    if bundle_id not in featured:
        featured = [bundle_id] + featured

    default_icon = app.get("iconURL", "")
    default_tint = app.get("tintColor", "")
    return {
        "name": source_cfg.get("name", existing.get("name", "ad-archer")),
        "subtitle": source_cfg.get("subtitle", existing.get("subtitle", "")),
        "description": source_cfg.get("description", existing.get("description", "")),
        "iconURL": source_cfg.get("iconURL", existing.get("iconURL", default_icon)),
        "headerURL": source_cfg.get(
            "headerURL",
            existing.get("headerURL", source_cfg.get("iconURL", existing.get("iconURL", default_icon))),
        ),
        "website": source_cfg.get("website", existing.get("website", "")),
        "tintColor": source_cfg.get("tintColor", existing.get("tintColor", default_tint)),
        "featuredApps": featured,
        "apps": merged_apps,
        "news": existing.get("news", []),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate/update AltStore source JSON from GitHub release + IPA metadata")
    parser.add_argument("--config", default="altstore/config.json")
    parser.add_argument("--output", default="altstore/source.json")
    parser.add_argument("--tag", default="")
    args = parser.parse_args()

    config = read_json_file(args.config)
    repo = config.get("release", {}).get("repo", "")
    if not repo:
        raise RuntimeError("Missing release.repo in config")
    asset_pattern = config.get("release", {}).get("asset_pattern", r"(?i)\.ipa$")

    if args.tag:
        tag = args.tag if args.tag.startswith("v") else f"v{args.tag}"
        release_url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    else:
        release_url = f"https://api.github.com/repos/{repo}/releases/latest"

    try:
        release_obj = fetch_json(release_url)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Failed to fetch GitHub release metadata: {e}") from e

    asset = choose_asset(release_obj, asset_pattern)

    existing = {}
    if os.path.exists(args.output):
        existing = read_json_file(args.output)

    with tempfile.TemporaryDirectory(prefix="ad-archer-altstore-") as td:
        ipa_path = os.path.join(td, asset.get("name") or "app.ipa")
        download_file(asset["browser_download_url"], ipa_path)
        ipa_meta = load_info_and_permissions(ipa_path)

    source = build_source(config, existing, release_obj, ipa_meta, asset)
    write_json_file(args.output, source)

    selected_bundle = config.get("app", {}).get("bundleIdentifier") or ipa_meta.get("bundleIdentifier")
    app = next((a for a in source["apps"] if a.get("bundleIdentifier") == selected_bundle), source["apps"][0])
    latest = app["versions"][0]
    print(
        f"Updated {args.output}: {app['bundleIdentifier']} {latest['version']} ({latest['buildVersion']}) "
        f"from {release_obj.get('tag_name', 'unknown')}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        raise SystemExit(1)
