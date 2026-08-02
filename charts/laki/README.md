# Laki

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/laki)](https://artifacthub.io/packages/search?repo=laki)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Helm chart for **Laki**, a multi-tenant notification engine written in Go. It dispatches
Email, SMS, Push, WhatsApp, Slack and Webhook notifications, renders localized templates,
and ships with rate limiting, circuit breaking, retries, a dead letter queue and
idempotency protection.

The chart deploys:

* the **backend** (`kargaw/laki`) — REST API on port `8080`, gRPC ingestion on port `50051`
* the **dashboard** (`kargaw/laki-ui`) — Next.js operations UI on port `3000`, optional

## TL;DR

```bash
helm repo add laki https://laki-n.github.io/laki
helm repo update
helm install my-laki laki/laki --namespace laki --create-namespace
```

## Prerequisites

* Kubernetes 1.21+
* Helm 3.8+
* A PostgreSQL (or Oracle) database — **not** provided by this chart
* A Redis instance for idempotency caching — **not** provided by this chart

## Installing

```bash
helm install my-laki laki/laki \
  --namespace laki --create-namespace \
  --set database.connectionString="postgres://laki:secret@postgres:5432/notification_db?sslmode=require" \
  --set redis.address="redis-master:6379" \
  --set backend.deliveryMode=sandbox \
  --set backend.webhookSecret.value="$(openssl rand -hex 32)"
```

Uninstall with:

```bash
helm uninstall my-laki --namespace laki
```

## Database

This chart does not bundle a database. Point `database.connectionString` at a PostgreSQL or
Oracle instance you already run, or supply the DSN through a Secret you manage:

```yaml
database:
  dialect: postgres
  existingSecret: laki-db
  existingSecretKey: DB_CONN_STRING
```

> **If no database is configured the backend silently falls back to an in-memory store.**
> The pod starts and `/healthz` returns OK, but templates, campaigns and delivery history
> are lost on every restart and are not shared between replicas. Treat a release without a
> database as a demo only.

The schema is **not** applied automatically. Before the first start, load
[`schema.sql`](https://github.com/laki-n/laki/blob/main/database/schema.sql) — or the files under
[`migrations/`](https://github.com/laki-n/laki/tree/main/database/migrations) — into your database.
A convenient way to do that as part of the release is `backend.initContainers`.

## Redis

Redis backs idempotency key deduplication. Set `redis.address` to your endpoint; set
`redis.enabled: false` to omit the wiring entirely, in which case deduplication degrades to
the SQL store.

## Secrets

Every credential in `values.yaml` is rendered into a single chart-managed Secret. If you
would rather not put secrets in a values file, you have two options:

1. Point the individual `existingSecret` fields at Secrets you manage
   (`database`, `redis`, `backend.webhookSecret`).
2. Set `secret.create: false` and inject everything through `backend.extraEnvFrom`:

   ```yaml
   secret:
     create: false
   backend:
     extraEnvFrom:
       - secretRef:
           name: laki-credentials   # DB_CONN_STRING, TWILIO_AUTH_TOKEN, ...
   ```

`backend.webhookSecret` guards inbound provider callbacks. Leaving it unset keeps the
application's built-in default HMAC key, which anyone reading the source can forge
signatures with — always set it for a real deployment.

## Delivery mode

`backend.deliveryMode` controls how far a notification travels:

| Mode | Behaviour |
|---|---|
| `mock` (default) | Nothing is handed to a provider. Safe for a first install. |
| `sandbox` | The full pipeline runs against provider sandboxes. |
| `live` | Messages are actually delivered. |

## Dashboard API base URL

The dashboard reads its API base from `NEXT_PUBLIC_API_BASE`. **Next.js inlines
`NEXT_PUBLIC_*` variables at image build time**, so setting `ui.apiBase` in this chart does
not change what the browser calls in the published `kargaw/laki-ui` image — that image was
built with the default `http://localhost:8080`.

Your options, in order of preference:

1. **Rebuild the dashboard image** with the right value baked in, and set `ui.image.repository`
   to your own image:

   ```bash
   docker build --build-arg NEXT_PUBLIC_API_BASE=https://laki.example.com -t myorg/laki-ui:v1.0.0 .
   ```

   (The upstream Dockerfile needs an `ARG NEXT_PUBLIC_API_BASE` / `ENV` pair added before
   `npm run build` for this to take effect.)
2. **Serve the API on the same origin as the dashboard.** Enable the chart's ingress: it
   routes `/v1` and `/healthz` to the backend and `/` to the dashboard on one host, so the
   baked-in `http://localhost:8080` is the only thing you have to override — and you can do
   that with a rebuild as above.
3. **Port-forward the backend to `localhost:8080`** on the machine running the browser. This
   is what the default `http://localhost:8080` expects, and it is fine for local evaluation.

`ui.apiBase` is still passed to the container, so it works for server-rendered requests and
for any image rebuilt with a matching build argument. Set `ui.enabled: false` to skip the
dashboard entirely.

## Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  host: laki.example.com
  tls:
    - secretName: laki-tls
      hosts:
        - laki.example.com
```

This produces one Ingress with `/v1` and `/healthz` routed to the backend and `/` routed to
the dashboard. Adjust `ingress.apiPaths` / `ingress.uiPath` if your controller needs a
different split. gRPC is **not** exposed through the Ingress — expose
`backend.service.grpcPort` with a `LoadBalancer` Service or a controller-specific gRPC route.

## Values

### Global

| Key | Type | Default | Description |
|---|---|---|---|
| `nameOverride` | string | `""` | Overrides the chart name used in resource names |
| `fullnameOverride` | string | `""` | Fully overrides the generated release name prefix |
| `imagePullSecrets` | list | `[]` | Image pull secrets applied to every pod |
| `commonLabels` | object | `{}` | Extra labels added to every resource |
| `commonAnnotations` | object | `{}` | Extra annotations added to every resource |
| `serviceAccount.create` | bool | `true` | Create a ServiceAccount |
| `serviceAccount.name` | string | `""` | ServiceAccount name; generated when empty |
| `serviceAccount.annotations` | object | `{}` | ServiceAccount annotations (IRSA, Workload Identity) |
| `serviceAccount.automountServiceAccountToken` | bool | `false` | Mount the API token into pods |
| `extraManifests` | list | `[]` | Extra manifests rendered as-is (templated) |

### Backend

| Key | Type | Default | Description |
|---|---|---|---|
| `backend.image.registry` | string | `docker.io` | Backend image registry |
| `backend.image.repository` | string | `kargaw/laki` | Backend image repository |
| `backend.image.tag` | string | `""` | Backend image tag; defaults to chart `appVersion` |
| `backend.image.pullPolicy` | string | `IfNotPresent` | Backend image pull policy |
| `backend.replicaCount` | int | `1` | Replicas; ignored when autoscaling is enabled |
| `backend.logLevel` | string | `info` | `debug`, `info`, `warn` or `error` |
| `backend.deliveryMode` | string | `mock` | `mock`, `sandbox` or `live` |
| `backend.defaultLocale` | string | `en` | Fallback locale |
| `backend.supportedLocales` | string | `en,am,om,ar,fr` | Accepted locales |
| `backend.webhookSecret.value` | string | `""` | Inbound webhook HMAC key |
| `backend.webhookSecret.existingSecret` | string | `""` | Read the HMAC key from this Secret |
| `backend.webhookSecret.existingSecretKey` | string | `WEBHOOK_SECRET` | Key inside that Secret |
| `backend.service.type` | string | `ClusterIP` | Backend Service type |
| `backend.service.httpPort` | int | `8080` | REST API Service port |
| `backend.service.grpcPort` | int | `50051` | gRPC Service port |
| `backend.service.httpNodePort` | string | `""` | NodePort for HTTP (NodePort Services only) |
| `backend.service.grpcNodePort` | string | `""` | NodePort for gRPC (NodePort Services only) |
| `backend.service.annotations` | object | `{}` | Backend Service annotations |
| `backend.service.extraPorts` | list | `[]` | Extra Service ports |
| `backend.containerPort` | int | `8080` | HTTP container port; always bound to `0.0.0.0` |
| `backend.grpcContainerPort` | int | `50051` | gRPC container port |
| `backend.resources` | object | `{}` | Backend resource requests/limits |
| `backend.livenessProbe.*` | object | probe on `/healthz` | Liveness probe tuning |
| `backend.readinessProbe.*` | object | probe on `/healthz` | Readiness probe tuning |
| `backend.startupProbe.*` | object | disabled | Startup probe tuning |
| `backend.customLivenessProbe` | object | `{}` | Replaces the chart-managed liveness probe |
| `backend.customReadinessProbe` | object | `{}` | Replaces the chart-managed readiness probe |
| `backend.customStartupProbe` | object | `{}` | Replaces the chart-managed startup probe |
| `backend.podSecurityContext` | object | non-root, `RuntimeDefault` | Pod security context |
| `backend.containerSecurityContext` | object | drops all capabilities | Container security context |
| `backend.autoscaling.enabled` | bool | `false` | Create an HPA for the backend |
| `backend.autoscaling.minReplicas` | int | `1` | HPA minimum replicas |
| `backend.autoscaling.maxReplicas` | int | `5` | HPA maximum replicas |
| `backend.autoscaling.targetCPUUtilizationPercentage` | int | `80` | HPA CPU target |
| `backend.autoscaling.targetMemoryUtilizationPercentage` | string | `""` | HPA memory target |
| `backend.autoscaling.behavior` | object | `{}` | Raw HPA behavior block |
| `backend.podDisruptionBudget.enabled` | bool | `false` | Create a PodDisruptionBudget |
| `backend.podDisruptionBudget.minAvailable` | int | `1` | PDB `minAvailable` |
| `backend.podDisruptionBudget.maxUnavailable` | string | `""` | PDB `maxUnavailable`; wins when set |
| `backend.updateStrategy` | object | `{type: RollingUpdate}` | Deployment strategy |
| `backend.terminationGracePeriodSeconds` | int | `30` | Drain window on shutdown |
| `backend.podLabels` | object | `{}` | Extra backend pod labels |
| `backend.podAnnotations` | object | `{}` | Extra backend pod annotations |
| `backend.nodeSelector` | object | `{}` | Backend node selector |
| `backend.tolerations` | list | `[]` | Backend tolerations |
| `backend.affinity` | object | `{}` | Backend affinity rules |
| `backend.topologySpreadConstraints` | list | `[]` | Backend topology spread constraints |
| `backend.priorityClassName` | string | `""` | Backend PriorityClass |
| `backend.extraEnv` | list | `[]` | Extra environment variables |
| `backend.extraEnvFrom` | list | `[]` | Extra ConfigMap/Secret env sources |
| `backend.extraVolumes` | list | `[]` | Extra volumes |
| `backend.extraVolumeMounts` | list | `[]` | Extra volume mounts |
| `backend.sidecars` | list | `[]` | Extra sidecar containers |
| `backend.initContainers` | list | `[]` | Extra init containers |

### Dashboard

| Key | Type | Default | Description |
|---|---|---|---|
| `ui.enabled` | bool | `true` | Deploy the dashboard |
| `ui.image.registry` | string | `docker.io` | Dashboard image registry |
| `ui.image.repository` | string | `kargaw/laki-ui` | Dashboard image repository |
| `ui.image.tag` | string | `""` | Dashboard image tag; defaults to chart `appVersion` |
| `ui.image.pullPolicy` | string | `IfNotPresent` | Dashboard image pull policy |
| `ui.replicaCount` | int | `1` | Dashboard replicas |
| `ui.apiBase` | string | `""` | API base URL; see "Dashboard API base URL" above |
| `ui.service.type` | string | `ClusterIP` | Dashboard Service type |
| `ui.service.port` | int | `3000` | Dashboard Service port |
| `ui.service.nodePort` | string | `""` | NodePort (NodePort Services only) |
| `ui.service.annotations` | object | `{}` | Dashboard Service annotations |
| `ui.containerPort` | int | `3000` | Dashboard container port |
| `ui.resources` | object | `{}` | Dashboard resource requests/limits |
| `ui.livenessProbe.*` | object | probe on `/` | Liveness probe tuning |
| `ui.readinessProbe.*` | object | probe on `/` | Readiness probe tuning |
| `ui.autoscaling.*` | object | disabled | Same shape as `backend.autoscaling` |
| `ui.podDisruptionBudget.*` | object | disabled | Same shape as `backend.podDisruptionBudget` |
| `ui.extraEnv` | list | `[]` | Extra environment variables |
| `ui.extraEnvFrom` | list | `[]` | Extra ConfigMap/Secret env sources |

The dashboard also accepts the same `podSecurityContext`, `containerSecurityContext`,
`updateStrategy`, `terminationGracePeriodSeconds`, `podLabels`, `podAnnotations`,
`nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints`, `priorityClassName`,
`extraVolumes`, `extraVolumeMounts`, `sidecars` and `initContainers` keys as the backend.

### Data stores and providers

| Key | Type | Default | Description |
|---|---|---|---|
| `database.dialect` | string | `postgres` | `postgres` or `oracle` |
| `database.connectionString` | string | `""` | Connection DSN |
| `database.existingSecret` | string | `""` | Read the DSN from this Secret |
| `database.existingSecretKey` | string | `DB_CONN_STRING` | Key inside that Secret |
| `redis.enabled` | bool | `true` | Wire the backend to Redis |
| `redis.address` | string | `redis-master:6379` | Redis `host:port` |
| `redis.password` | string | `""` | Redis password |
| `redis.existingSecret` | string | `""` | Read the password from this Secret |
| `redis.existingSecretKey` | string | `REDIS_PASSWORD` | Key inside that Secret |
| `kafka.enabled` | bool | `false` | Start the Kafka ingestion consumer |
| `kafka.brokers` | string | `kafka:9092` | Comma separated broker list |
| `kafka.topic` | string | `notifications.events` | Topic to consume |
| `kafka.groupId` | string | `notification-service-group` | Consumer group id |
| `providers.email.active` | string | `mock` | `ses`, `mailjet`, `local_http` or `mock` |
| `providers.email.awsRegion` | string | `us-east-1` | SES region |
| `providers.email.senderEmail` | string | `""` | Mailjet from address |
| `providers.email.apiKey` | string | `""` | Mailjet API key |
| `providers.email.apiSecret` | string | `""` | Mailjet API secret |
| `providers.sms.active` | string | `mock` | `twilio`, `afro_sms`, `local` or `mock` |
| `providers.sms.localEndpoint` | string | `http://localhost:9090/api/sms/send` | Endpoint for the `local` adapter |
| `providers.sms.twilio.accountSid` | string | `""` | Twilio account SID |
| `providers.sms.twilio.authToken` | string | `""` | Twilio auth token |
| `providers.sms.afro.url` | string | `https://api.afromessage.com/api` | AfroMessage base URL |
| `providers.sms.afro.token` | string | `""` | AfroMessage API token |
| `providers.sms.afro.sender` | string | `Default` | AfroMessage sender id |
| `providers.push.active` | string | `mock` | `fcm` or `mock` |
| `providers.push.serverKey` | string | `""` | FCM server key |

### Networking and packaging

| Key | Type | Default | Description |
|---|---|---|---|
| `ingress.enabled` | bool | `false` | Create an Ingress |
| `ingress.className` | string | `""` | IngressClass name |
| `ingress.annotations` | object | `{}` | Ingress annotations |
| `ingress.host` | string | `""` | Hostname; **required** when the Ingress is enabled |
| `ingress.pathType` | string | `Prefix` | Path type for generated rules |
| `ingress.apiPaths` | list | `["/v1", "/healthz"]` | Paths routed to the backend |
| `ingress.uiPath` | string | `/` | Path routed to the dashboard |
| `ingress.tls` | list | `[]` | Ingress TLS blocks |
| `ingress.extraRules` | list | `[]` | Extra rules appended to the Ingress |
| `networkPolicy.enabled` | bool | `false` | Create a NetworkPolicy for the backend |
| `networkPolicy.allowExternal` | bool | `true` | Allow traffic from any source |
| `networkPolicy.ingressNamespaceSelectors` | list | `[]` | Namespaces allowed to reach the backend |
| `networkPolicy.ingressPodSelectors` | list | `[]` | Pods allowed to reach the backend |
| `secret.create` | bool | `true` | Render the chart-managed Secret |
| `secret.annotations` | object | `{}` | Annotations for that Secret |
| `tests.enabled` | bool | `true` | Render the `helm test` connection pod |

## Verifying the chart signature

Every published chart is signed, and carries a `.prov` provenance file alongside the
tarball. To check it:

```bash
curl -sO https://laki-n.github.io/laki/KEYS
gpg --dearmor < KEYS > laki.gpg

helm pull laki/laki --prov
helm verify --keyring laki.gpg laki-*.tgz
```

Expect the signing key `Laki Charts <abduselamm555@gmail.com>`, fingerprint
`54CF AFC3 BFED 9EF3 CAD5  C0A8 A295 BCE9 CB0A B640`.

To verify as part of an install, pass `--verify` with the same keyring:

```bash
helm install my-laki laki/laki --verify --keyring laki.gpg
```

## Verifying a release

```bash
helm test my-laki --namespace laki
```

This runs a pod that curls `/healthz` on the backend Service.

## Upgrading

The chart is versioned independently of the application. Check `appVersion` in `Chart.yaml`
to see which Laki release a chart version ships by default, and pin `backend.image.tag` /
`ui.image.tag` if you want to move the two independently.

## License

MIT. See [LICENSE](https://github.com/laki-n/laki/blob/main/LICENSE).
