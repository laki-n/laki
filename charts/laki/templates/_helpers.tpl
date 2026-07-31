{{/*
Chart name, overridable.
*/}}
{{- define "laki.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified release name.
*/}}
{{- define "laki.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "laki.backend.fullname" -}}
{{- printf "%s-backend" (include "laki.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "laki.ui.fullname" -}}
{{- printf "%s-ui" (include "laki.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "laki.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels shared by every resource in the chart.
*/}}
{{- define "laki.labels" -}}
helm.sh/chart: {{ include "laki.chart" . }}
{{ include "laki.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: laki
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "laki.selectorLabels" -}}
app.kubernetes.io/name: {{ include "laki.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "laki.backend.labels" -}}
{{ include "laki.labels" . }}
app.kubernetes.io/component: backend
{{- end -}}

{{- define "laki.backend.selectorLabels" -}}
{{ include "laki.selectorLabels" . }}
app.kubernetes.io/component: backend
{{- end -}}

{{- define "laki.ui.labels" -}}
{{ include "laki.labels" . }}
app.kubernetes.io/component: ui
{{- end -}}

{{- define "laki.ui.selectorLabels" -}}
{{ include "laki.selectorLabels" . }}
app.kubernetes.io/component: ui
{{- end -}}

{{/*
Annotations shared by every resource in the chart.
*/}}
{{- define "laki.commonAnnotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end -}}

{{- define "laki.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "laki.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Assemble a fully qualified image reference from a registry/repository/tag block.
Usage: include "laki.image" (dict "image" .Values.backend.image "context" $)
*/}}
{{- define "laki.image" -}}
{{- $image := .image -}}
{{- $tag := $image.tag | default .context.Chart.AppVersion -}}
{{- if $image.registry -}}
{{- printf "%s/%s:%s" $image.registry $image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $image.repository $tag -}}
{{- end -}}
{{- end -}}

{{- define "laki.imagePullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Name of the chart-managed Secret.
*/}}
{{- define "laki.secretName" -}}
{{- printf "%s-secrets" (include "laki.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "laki.configMapName" -}}
{{- printf "%s-config" (include "laki.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
True when the chart-managed Secret has at least one key to render.
*/}}
{{- define "laki.secret.hasData" -}}
{{- $v := .Values -}}
{{- $any := false -}}
{{- if and (not $v.database.existingSecret) $v.database.connectionString -}}{{- $any = true -}}{{- end -}}
{{- if and (not $v.backend.webhookSecret.existingSecret) $v.backend.webhookSecret.value -}}{{- $any = true -}}{{- end -}}
{{- if and $v.redis.enabled (not $v.redis.existingSecret) $v.redis.password -}}{{- $any = true -}}{{- end -}}
{{- if $v.providers.email.apiKey -}}{{- $any = true -}}{{- end -}}
{{- if $v.providers.email.apiSecret -}}{{- $any = true -}}{{- end -}}
{{- if $v.providers.sms.twilio.authToken -}}{{- $any = true -}}{{- end -}}
{{- if $v.providers.sms.afro.token -}}{{- $any = true -}}{{- end -}}
{{- if $v.providers.push.serverKey -}}{{- $any = true -}}{{- end -}}
{{- if $any -}}true{{- end -}}
{{- end -}}

{{- define "laki.secret.enabled" -}}
{{- if and .Values.secret.create (include "laki.secret.hasData" .) -}}true{{- end -}}
{{- end -}}

{{/*
In-cluster base URL of the backend REST API.
*/}}
{{- define "laki.backend.internalUrl" -}}
{{- printf "http://%s:%v" (include "laki.backend.fullname" .) .Values.backend.service.httpPort -}}
{{- end -}}

{{/*
Base URL the browser uses to reach the API. Explicit value wins; otherwise it is
derived from the ingress host, falling back to the upstream image default.
*/}}
{{- define "laki.ui.apiBase" -}}
{{- if .Values.ui.apiBase -}}
{{- .Values.ui.apiBase -}}
{{- else if and .Values.ingress.enabled .Values.ingress.host -}}
{{- $scheme := ternary "https" "http" (gt (len .Values.ingress.tls) 0) -}}
{{- printf "%s://%s" $scheme .Values.ingress.host -}}
{{- else -}}
http://localhost:8080
{{- end -}}
{{- end -}}

{{/*
Environment variables sourced from Secrets, shared by the backend container.
Each entry is emitted only when a value or an existing Secret is configured, so
the container falls back to the application default otherwise.
*/}}
{{- define "laki.backend.secretEnv" -}}
{{- $v := .Values -}}
{{- $chartSecret := include "laki.secretName" . -}}
{{- /* When the chart Secret is disabled the operator supplies these through
       backend.extraEnvFrom, so referencing a Secret we never render would
       leave the pod stuck in CreateContainerConfigError. */ -}}
{{- $managed := include "laki.secret.enabled" . -}}
{{- if $v.database.existingSecret }}
- name: DB_CONN_STRING
  valueFrom:
    secretKeyRef:
      name: {{ $v.database.existingSecret }}
      key: {{ $v.database.existingSecretKey }}
{{- else if and $managed $v.database.connectionString }}
- name: DB_CONN_STRING
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: DB_CONN_STRING
{{- end }}
{{- if $v.backend.webhookSecret.existingSecret }}
- name: WEBHOOK_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $v.backend.webhookSecret.existingSecret }}
      key: {{ $v.backend.webhookSecret.existingSecretKey }}
{{- else if and $managed $v.backend.webhookSecret.value }}
- name: WEBHOOK_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: WEBHOOK_SECRET
{{- end }}
{{- if $v.redis.enabled }}
{{- if $v.redis.existingSecret }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $v.redis.existingSecret }}
      key: {{ $v.redis.existingSecretKey }}
{{- else if and $managed $v.redis.password }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: REDIS_PASSWORD
{{- end }}
{{- end }}
{{- if and $managed $v.providers.email.apiKey }}
- name: EMAIL_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: EMAIL_API_KEY
{{- end }}
{{- if and $managed $v.providers.email.apiSecret }}
- name: EMAIL_API_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: EMAIL_API_SECRET
{{- end }}
{{- if and $managed $v.providers.sms.twilio.authToken }}
- name: TWILIO_AUTH_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: TWILIO_AUTH_TOKEN
{{- end }}
{{- if and $managed $v.providers.sms.afro.token }}
- name: SMS_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: SMS_TOKEN
{{- end }}
{{- if and $managed $v.providers.push.serverKey }}
- name: FCM_SERVER_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $chartSecret }}
      key: FCM_SERVER_KEY
{{- end }}
{{- end -}}
