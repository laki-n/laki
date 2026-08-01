#!/usr/bin/env python3
"""Keep the chart in step with the published Laki images.

Polls Docker Hub for kargaw/laki and kargaw/laki-ui and decides whether the
chart needs a new release:

  * a newer semver tag appeared        -> minor chart bump, appVersion moves
  * the pinned tag was rebuilt in place -> patch chart bump, appVersion stays

The second case is the one a version-only watcher misses. Security rebuilds are
published onto the existing tag, so the digest is the only signal that anything
changed - and a chart bump is what makes Artifact Hub re-run its security scan.

Writes the decision to $GITHUB_OUTPUT (when set) and edits Chart.yaml,
values.yaml and the state file in place. Prints the plan and exits 0 with
changed=false when there is nothing to do.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CHART_YAML = REPO_ROOT / "charts" / "laki" / "Chart.yaml"
VALUES_YAML = REPO_ROOT / "charts" / "laki" / "values.yaml"
STATE_FILE = REPO_ROOT / ".github" / "image-state.json"

IMAGES = {
    "backend": "kargaw/laki",
    "ui": "kargaw/laki-ui",
}

SEMVER_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def fail(message: str) -> "None":
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def fetch_tags(repository: str) -> list[dict]:
    """Return every tag Docker Hub knows about for a public repository."""
    url = f"https://hub.docker.com/v2/repositories/{repository}/tags?page_size=100"
    tags: list[dict] = []
    while url:
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
        except urllib.error.URLError as exc:
            fail(f"could not read tags for {repository}: {exc}")
        tags.extend(payload.get("results", []))
        url = payload.get("next")
    if not tags:
        fail(f"{repository} reported no tags at all - refusing to guess")
    return tags


def newest_release(repository: str) -> tuple[str, str]:
    """Highest semver tag for a repository, with the digest it currently points at."""
    candidates = []
    for tag in fetch_tags(repository):
        match = SEMVER_TAG.match(tag.get("name", ""))
        digest = tag.get("digest")
        # A tag mid-push can appear without a digest; it is not a stable target.
        if match and digest:
            candidates.append((tuple(int(p) for p in match.groups()), tag["name"], digest))
    if not candidates:
        fail(f"{repository} has no vX.Y.Z tag with a digest")
    candidates.sort()
    _, name, digest = candidates[-1]
    return name, digest


def read_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError as exc:
        fail(f"{STATE_FILE} is not valid JSON: {exc}")
    return {}


def bump(version: str, part: str) -> str:
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", version)
    if not match:
        fail(f"chart version {version!r} is not plain X.Y.Z")
    major, minor, patch = (int(p) for p in match.groups())
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def replace_once(text: str, pattern: str, replacement: str, what: str) -> str:
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        fail(f"expected exactly one {what} to update, matched {count}")
    return new_text


def set_ui_tag(text: str, value: str) -> str:
    """Set ui.image.tag without disturbing the identically-named backend key.

    Walks the file by indentation rather than pattern-matching `tag:`, because
    backend.image.tag and ui.image.tag are textually identical.
    """
    lines = text.split("\n")
    in_ui = in_image = False
    for index, line in enumerate(lines):
        if re.match(r"^ui:\s*$", line):
            in_ui = True
            continue
        if in_ui and re.match(r"^\S", line):  # next top-level key ends the ui block
            break
        if in_ui and re.match(r"^  image:\s*$", line):
            in_image = True
            continue
        if in_image and re.match(r"^  \S", line):  # next key at image's level
            in_image = False
        if in_image and re.match(r"^    tag:", line):
            lines[index] = f'    tag: "{value}"' if value else '    tag: ""'
            return "\n".join(lines)
    fail("could not locate ui.image.tag in values.yaml")
    return text


def main() -> None:
    latest = {}
    for key, repository in IMAGES.items():
        tag, digest = newest_release(repository)
        latest[key] = {"tag": tag, "digest": digest}
        print(f"{repository}: {tag} @ {digest[:19]}...")

    state = read_state()
    if state == latest:
        print("No image change since the last sync.")
        emit(changed=False)
        return

    if not state:
        # First run: record what is published today as the baseline. Bumping the
        # chart here would ship a release that changes nothing.
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(latest, indent=2, sort_keys=True) + "\n")
        print("Seeded the image baseline; no chart change needed.")
        emit(changed=True, seeded=True, summary="Record the current published image digests")
        return

    chart_text = CHART_YAML.read_text()
    # `\s` matches newlines, so every anchored edit below uses [ \t] instead -
    # otherwise `\s*$` swallows the blank line that follows the key.
    current_app = re.search(r'^appVersion:[ \t]*"?([^"\n]+?)"?[ \t]*$', chart_text, re.MULTILINE)
    current_ver = re.search(r"^version:[ \t]*(\S+)[ \t]*$", chart_text, re.MULTILINE)
    if not current_app or not current_ver:
        fail("could not read version/appVersion from Chart.yaml")
    app_version = current_app.group(1).strip()
    chart_version = current_ver.group(1).strip()

    backend_tag = latest["backend"]["tag"]
    ui_tag = latest["ui"]["tag"]

    version_moved = backend_tag != app_version or (
        state and state.get("ui", {}).get("tag") not in (None, ui_tag)
    )
    part = "minor" if version_moved else "patch"
    new_chart_version = bump(chart_version, part)

    reasons = []
    for key, repository in IMAGES.items():
        was = state.get(key, {})
        now = latest[key]
        if not was:
            reasons.append(f"{repository} tracked at {now['tag']}")
        elif was.get("tag") != now["tag"]:
            reasons.append(f"{repository} released {now['tag']} (was {was['tag']})")
        elif was.get("digest") != now["digest"]:
            reasons.append(f"{repository}:{now['tag']} rebuilt upstream")

    # appVersion follows the backend; the dashboard only needs an explicit tag
    # when the two drift apart, since values.yaml defaults it to appVersion.
    chart_text = replace_once(
        chart_text, r"^version:[ \t]*\S+[ \t]*$", f"version: {new_chart_version}", "chart version"
    )
    chart_text = replace_once(
        chart_text, r"^appVersion:[ \t]*.*$", f'appVersion: "{backend_tag}"', "appVersion"
    )
    chart_text = replace_once(
        chart_text,
        r"^      image: docker\.io/kargaw/laki:\S+[ \t]*$",
        f"      image: docker.io/kargaw/laki:{backend_tag}",
        "backend image annotation",
    )
    chart_text = replace_once(
        chart_text,
        r"^      image: docker\.io/kargaw/laki-ui:\S+[ \t]*$",
        f"      image: docker.io/kargaw/laki-ui:{ui_tag}",
        "dashboard image annotation",
    )

    changes = "\n".join(
        f"    - kind: {'changed' if version_moved else 'security'}\n"
        f"      description: {reason}"
        for reason in reasons
    )
    chart_text = replace_once(
        chart_text,
        r"^  artifacthub\.io/changes: \|\n(?:    .*\n?)*",
        f"  artifacthub.io/changes: |\n{changes}\n",
        "changes annotation",
    )
    CHART_YAML.write_text(chart_text)

    values_text = VALUES_YAML.read_text()
    updated_values = set_ui_tag(values_text, "" if ui_tag == backend_tag else ui_tag)
    if updated_values != values_text:
        VALUES_YAML.write_text(updated_values)
        print(f"values.yaml: pinned ui.image.tag to {ui_tag or 'appVersion'}")

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(latest, indent=2, sort_keys=True) + "\n")

    summary = "; ".join(reasons) or "image state refreshed"
    print(f"chart {chart_version} -> {new_chart_version} ({part}): {summary}")
    emit(
        changed=True,
        chart_version=new_chart_version,
        app_version=backend_tag,
        bump=part,
        summary=summary,
        body="\n".join(f"- {reason}" for reason in reasons),
    )


def emit(**outputs) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in outputs.items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            if "\n" in str(value):
                handle.write(f"{key}<<__EOF__\n{value}\n__EOF__\n")
            else:
                handle.write(f"{key}={value}\n")


if __name__ == "__main__":
    main()
