# Publishing the Laki chart to Artifact Hub

Artifact Hub does not host charts. It indexes a Helm repository that you host, then renders
its packages. So there are three things to get right, in order: publish a Helm repository,
register it on Artifact Hub, then prove you own it.

This repository (`laki-n/laki`) is public and exists solely to host the chart. The
application source lives elsewhere and is private, which is why nothing here links to it —
every URL Artifact Hub renders has to resolve for anonymous visitors.

Steps 1 to 5 are one-time setup. Steps 6 and 7 are the ongoing loop: the image watcher
proposes version bumps, and merging its pull request cuts the release.

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
for `kargaw/laki` and `kargaw/laki-ui`, and opens a pull request when either moves:

| What it sees | What it does |
|---|---|
| A newer `vX.Y.Z` tag | Minor chart bump; `appVersion` and the image annotations move to the new tag |
| The pinned tag rebuilt in place (same tag, new digest) | Patch chart bump; `appVersion` unchanged, logged as a `security` change |
| Nothing | Exits quietly, no pull request |

The second row is the one that matters in practice. Security fixes are published onto the
existing tag rather than a new version, so the digest is the only evidence anything changed —
and a chart bump is what makes Artifact Hub re-run its scan against the rebuilt image.

The last seen tags and digests are recorded in
[`.github/image-state.json`](.github/image-state.json). That file is the comparison baseline;
deleting it makes the next run re-seed rather than report a change.

The workflow lints and renders the chart before opening the pull request, and reuses the
`chore/sync-images` branch so repeated detections amend one pull request instead of piling
up. Nothing reaches Artifact Hub until you merge — merging triggers the release below.

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
* Artifact Hub re-scans the index roughly every 30 minutes. A missing new version usually
  means the chart `version` was not bumped.
* The repository page on Artifact Hub reports scan errors under **Control Panel →
  Repositories → (…) → Errors log**. Check there first when something does not appear.
