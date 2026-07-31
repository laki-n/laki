# Laki Helm Charts

Helm chart repository for **[Laki](https://hub.docker.com/r/kargaw/laki)**, a multi-tenant
notification engine written in Go that dispatches Email, SMS, Push, WhatsApp, Slack and
Webhook notifications.

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/laki)](https://artifacthub.io/packages/search?repo=laki)
[![Lint Helm Chart](https://github.com/laki-n/laki/actions/workflows/lint-chart.yml/badge.svg)](https://github.com/laki-n/laki/actions/workflows/lint-chart.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Usage

```bash
helm repo add laki https://laki-n.github.io/laki
helm repo update
helm search repo laki
```

Install the chart:

```bash
helm install my-laki laki/laki \
  --namespace laki --create-namespace \
  --set database.connectionString="postgres://laki:secret@postgres:5432/notification_db?sslmode=require" \
  --set redis.address="redis-master:6379" \
  --set backend.deliveryMode=sandbox
```

PostgreSQL and Redis are **not** bundled — point the chart at instances you already run.

## Charts

| Chart | Description |
|---|---|
| [`laki`](charts/laki) | Notification backend (REST + gRPC) and the optional Next.js operations dashboard |

Full configuration reference: **[charts/laki/README.md](charts/laki/README.md)**.

## Repository layout

```
charts/laki/          the chart
database/             schema.sql and migrations to load before first start
artifacthub-repo.yml  Artifact Hub ownership metadata, published to gh-pages
RELEASING.md          how a new chart version reaches Artifact Hub
```

The packaged charts and `index.yaml` live on the [`gh-pages`](../../tree/gh-pages) branch,
served by GitHub Pages and indexed by Artifact Hub.

## Container images

| Image | Registry |
|---|---|
| `kargaw/laki` | [Docker Hub](https://hub.docker.com/r/kargaw/laki) |
| `kargaw/laki-ui` | [Docker Hub](https://hub.docker.com/r/kargaw/laki-ui) |

## Contributing

Chart changes need `version` bumped in [`charts/laki/Chart.yaml`](charts/laki/Chart.yaml) —
`chart-releaser` keys off that version, so without a bump nothing is published. See
[RELEASING.md](RELEASING.md).

Validate locally before opening a pull request:

```bash
helm lint --strict charts/laki
helm template test charts/laki
helm template test charts/laki -f charts/laki/ci/full-values.yaml
```

## License

[MIT](LICENSE)
