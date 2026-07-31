# Laki Helm chart repository

This branch is served by GitHub Pages and holds the packaged charts and `index.yaml`.
It is written by [chart-releaser](https://github.com/helm/chart-releaser-action); do not
edit it by hand.

```bash
helm repo add laki https://laki-n.github.io/laki
helm repo update
helm install my-laki laki/laki
```

Chart sources live on the [`main`](../../tree/main) branch.
