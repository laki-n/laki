# Publishing the Laki chart to Artifact Hub

Artifact Hub does not host charts. It indexes a Helm repository that you host, then renders
its packages. So there are three things to get right, in order: publish a Helm repository,
register it on Artifact Hub, then prove you own it.

This repository (`laki-n/laki`) is public and exists solely to host the chart. The
application source lives elsewhere and is private, which is why nothing here links to it —
every URL Artifact Hub renders has to resolve for anonymous visitors.

Steps 1 to 5 are one-time setup. Steps 6 and 7 are the ongoing loop, and they run
themselves: the image watcher bumps the chart when upstream images move, and that push
cuts the release.

## 1. Create the `gh-pages` branch

`chart-releaser` publishes `index.yaml` to a branch; it does not create that branch for you.
Run this once, from a clone of this repository:

```bash
git checkout --orphan gh-pages
git rm -rf .
echo "Laki Helm chart repository" > README.md
git add README.md
git commit -m "Initialize Helm chart repository"
git push origin gh-pages
git checkout main
```

## 2. Enable GitHub Pages

In the repository: **Settings → Pages → Build and deployment**

* Source: *Deploy from a branch*
* Branch: `gh-pages`, folder `/ (root)`

Wait for the first deploy, then confirm the site answers:

```bash
curl -I https://laki-n.github.io/laki/
```

## 3. Check the workflow permissions

**Settings → Actions → General → Workflow permissions** must be
*Read and write permissions*, otherwise `chart-releaser` cannot create releases or push to
`gh-pages`.

## 4. Cut the first chart release

Merge `charts/` to `main`. The [`release-chart.yml`](.github/workflows/release-chart.yml)
workflow will:

1. package `charts/laki` because its `version` in `Chart.yaml` has no matching release yet,
2. create the GitHub release `laki-1.0.0` with `laki-1.0.0.tgz` attached,
3. write `index.yaml` to `gh-pages`.

Verify:

```bash
curl -s https://laki-n.github.io/laki/index.yaml
helm repo add laki https://laki-n.github.io/laki
helm search repo laki
```

## 5. Register the repository on Artifact Hub

1. Sign in at <https://artifacthub.io/> (a GitHub login is fine).
2. **Control Panel → Repositories → Add repository**.
   * Kind: **Helm charts**
   * Name: `laki` — this becomes the URL, `artifacthub.io/packages/helm/laki/laki`, and it
     is also the value in the Artifact Hub badge in the chart README.
   * Display name: `Laki`
   * URL: `https://laki-n.github.io/laki`
3. Save. The first index scan usually lands within about 30 minutes.

### Claim ownership (the "Verified publisher" badge)

1. Copy the **Repository ID** shown for the repository in the control panel.
2. Fill both placeholders in [`artifacthub-repo.yml`](artifacthub-repo.yml): the repository ID,
   and the e-mail address of your Artifact Hub account. The e-mail must match exactly.
3. Commit to `main`. The release workflow copies the file to the root of `gh-pages`, where
   Artifact Hub looks for it on the next scan.

## 6. Automatic image tracking

[`watch-images.yml`](.github/workflows/watch-images.yml) polls Docker Hub every six hours
for `kargaw/laki` and `kargaw/laki-ui`, and bumps the chart when either moves:

| What it sees | What it does |
|---|---|
| A newer `vX.Y.Z` tag | Minor chart bump; `appVersion` and the image annotations move to the new tag |
| The pinned tag rebuilt in place (same tag, new digest) | Patch chart bump; `appVersion` unchanged, logged as a `security` change |
| Nothing | Exits quietly, nothing committed |

The second row is the one that matters in practice. Security fixes are published onto the
existing tag rather than a new version, so the digest is the only evidence anything changed —
and a chart bump is what makes Artifact Hub re-run its scan against the rebuilt image.

The last seen tags and digests are recorded in
[`.github/image-state.json`](.github/image-state.json). That file is the comparison baseline;
deleting it makes the next run re-seed rather than report a change.

The workflow lints and renders the chart before committing, then pushes straight to `main`
and explicitly dispatches the release workflow.

That dispatch is not optional. GitHub suppresses workflow triggers for pushes authenticated
with `GITHUB_TOKEN`, so the bump would otherwise land on `main` and never be packaged —
leaving a chart version that exists in git but not on Artifact Hub. This bit us once, between
chart 1.0.1 and 1.0.2.

**Why it does not open a pull request:** the `laki-n` organisation forbids GitHub Actions
from creating pull requests (*Settings → Actions → Allow GitHub Actions to create and approve
pull requests*), so a review step would never actually run. Every change the watcher makes is
generated from the published digests, validated before it lands, and revertable like any other
commit. Enable that org setting if you would rather review these first.

If the backend and dashboard ever release different versions, the workflow pins
`ui.image.tag` in `values.yaml` (it otherwise defaults to `appVersion`).

**Why polling rather than a webhook:** the application repositories are private and this one
cannot receive a `repository_dispatch` from them without a personal access token stored as a
secret in both. Docker Hub is public, so watching the published artefact needs no credentials
at all. To switch to push-based later, add a `repository_dispatch` step to each publish
workflow and give this repository a matching trigger.

## 7. Releasing a new chart version

`chart-releaser` keys off the chart version, not off git tags. Every user-visible change to
`charts/laki/**` needs `version` bumped in `Chart.yaml`, or nothing is published.

* **Chart-only change** (template fix, new value): bump `version` — patch or minor per
  semver. Leave `appVersion` alone.
* **New Laki release**: set `appVersion` to the new image tag, bump `version`, and update the
  `artifacthub.io/images` annotation so Artifact Hub's security report scans the right tags.

Also update `artifacthub.io/changes` in `Chart.yaml` — Artifact Hub renders it as the
changelog for that version. Valid `kind` values are `added`, `changed`, `deprecated`,
`removed`, `fixed` and `security`.

Then merge to `main`; the workflow does the rest.

## Notes

* `chart-releaser` tags releases `laki-<version>`, e.g. `laki-1.0.0`. Do not hand-create
  `v*.*.*` tags here — image builds happen in the application repository, not this one.
* **The control panel's "next check in ~N minutes" is optimistic.** Two consecutive
  tracking runs on this repository were measured at `2026-07-31 21:10:41` and
  `2026-08-01 21:10:17` — almost exactly 24 hours apart, not 30 minutes. Budget a day for
  anything that depends on a re-track, and do not read a stale "Last processed" with a green
  tick as a failure.
* That cadence has a sharp edge: `artifacthub-repo.yml` was first served 15 seconds *after*
  a tracking run, so the verified-publisher badge sat unset for a full day. If a change is
  not picked up, publishing a chart version is the reliable nudge — it changes the index
  digest and forces a full re-read.
* A missing new version on Artifact Hub usually means the chart `version` was not bumped.
* The repository page on Artifact Hub reports scan errors under **Control Panel →
  Repositories → (…) → Errors log**. Check there first when something does not appear.
