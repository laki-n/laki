#!/usr/bin/env python3
"""Keep the chart in step with the published Laki images.

Polls the GitHub Container Registry for the laki-n images and decides whether the
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

REGISTRY = "ghcr.io"

IMAGES = {
    "backend": "laki-n/laki",
    "ui": "laki-n/laki-ui",
}

SEMVER_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")

# Asking for every manifest type means the registry returns the digest of the
# multi-arch index rather than of one architecture's manifest, so the digest is
# stable regardless of which platform happens to be listed first.
MANIFEST_TYPES = ", ".join(
    (
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    )
)


def fail(message: str) -> "None":
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def request(url: str, headers: dict, method: str = "GET"):
    req = urllib.request.Request(url, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=30)


def pull_token(repository: str) -> str:
    """Anonymous pull token. Only works while the package is public."""
    url = f"https://{REGISTRY}/token?scope=repository:{repository}:pull&service={REGISTRY}"
    try:
        with request(url, {"Accept": "application/json"}) as response:
            return json.load(response)["token"]
    except urllib.error.HTTPError as exc:
        fail(
            f"could not get a pull token for {repository} ({exc.code}). "
            "If the package exists, check that its visibility is public."
        )
    except urllib.error.URLError as exc:
        fail(f"could not reach {REGISTRY} for {repository}: {exc}")
    return ""


def fetch_tags(repository: str, token: str) -> list[str]:
    """Every tag the registry lists, following pagination."""
    url = f"https://{REGISTRY}/v2/{repository}/tags/list?n=100"
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    tags: list[str] = []
    while url:
        try:
            with request(url, headers) as response:
                payload = json.load(response)
                link = response.headers.get("Link", "")
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                fail(
                    f"{repository} is not readable anonymously ({exc.code}). "
                    "Set the package visibility to public."
                )
            if exc.code == 404:
                fail(f"{repository} does not exist in {REGISTRY} yet.")
            fail(f"could not list tags for {repository}: {exc}")
        except urllib.error.URLError as exc:
            fail(f"could not list tags for {repository}: {exc}")
        tags.extend(payload.get("tags") or [])
        # Link: </v2/...?last=...&n=100>; rel="next"
        match = re.search(r'<([^>]+)>;\s*rel="next"', link)
        url = f"https://{REGISTRY}{match.group(1)}" if match else None
    if not tags:
        fail(f"{repository} reported no tags at all - refusing to guess")
    return tags


def fetch_digest(repository: str, tag: str, token: str) -> str:
    url = f"https://{REGISTRY}/v2/{repository}/manifests/{tag}"
    headers = {"Authorization": f"Bearer {token}", "Accept": MANIFEST_TYPES}
    try:
        with request(url, headers, method="HEAD") as response:
            digest = response.headers.get("Docker-Content-Digest")
    except urllib.error.HTTPError as exc:
        fail(f"could not read the manifest for {repository}:{tag}: {exc}")
    except urllib.error.URLError as exc:
        fail(f"could not read the manifest for {repository}:{tag}: {exc}")
    if not digest:
        fail(f"{repository}:{tag} returned no digest header")
    return digest


def newest_release(repository: str) -> tuple[str, str]:
    """Highest semver tag for a repository, with the digest it currently points at."""
    token = pull_token(repository)
    candidates = []
    for name in fetch_tags(repository, token):
        match = SEMVER_TAG.match(name)
        # Registries also carry sha256-* tags for signatures and attestations;
        # the semver filter drops them.
        if match:
            candidates.append((tuple(int(p) for p in match.groups()), name))
    if not candidates:
        fail(f"{repository} has no vX.Y.Z tag")
    candidates.sort()
    name = candidates[-1][1]
    return name, fetch_digest(repository, name, token)


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
        r"^      image: ghcr\.io/laki-n/laki:\S+[ \t]*$",
        f"      image: ghcr.io/laki-n/laki:{backend_tag}",
        "backend image annotation",
    )
    chart_text = replace_once(
        chart_text,
        r"^      image: ghcr\.io/laki-n/laki-ui:\S+[ \t]*$",
        f"      image: ghcr.io/laki-n/laki-ui:{ui_tag}",
        "dashboard image annotation",
    )

    # An in-place rebuild of an already-published tag is how upstream ships
    # security fixes, so tell Artifact Hub to flag the version accordingly.
    chart_text = replace_once(
        chart_text,
        r"^  artifacthub\.io/containsSecurityUpdates:[ \t]*.*$",
        f'  artifacthub.io/containsSecurityUpdates: "{str(not version_moved).lower()}"',
        "containsSecurityUpdates annotation",
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
