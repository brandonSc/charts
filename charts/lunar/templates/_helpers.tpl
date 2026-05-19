{{/*
Expand the name of the chart.
*/}}
{{- define "lunar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "lunar.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "lunar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "lunar.labels" -}}
helm.sh/chart: {{ include "lunar.chart" . }}
{{ include "lunar.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "lunar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lunar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "lunar.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lunar.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace where script pods run. Defaults to the release namespace.
*/}}
{{- define "lunar.scriptNamespace" -}}
{{- .Values.operator.scriptNamespace | default .Release.Namespace }}
{{- end }}

{{/*
Fail fast when GitHub App auth is misconfigured.
*/}}
{{- define "lunar.githubAuthCheck" -}}
{{- $hasApps := gt (len .Values.hub.github.apps) 0 -}}
{{- $hasLegacy := or (gt (int .Values.hub.github.app.id) 0) (gt (int .Values.hub.github.app.installId) 0) -}}
{{- if and $hasApps $hasLegacy -}}
{{- fail "hub.github.apps is mutually exclusive with hub.github.app.id / hub.github.app.installId. Use one mode or the other." -}}
{{- end -}}
{{- if $hasApps -}}
{{- include "lunar.githubAppsCheck" . -}}
{{- else -}}
{{- if not (gt (int .Values.hub.github.app.id) 0) -}}
{{- fail "hub.github.app.id is required (numeric, non-zero), or use hub.github.apps for multi-App routing. Run scripts/create-github-app.sh in the lunar repo to create one if you don't have it yet." -}}
{{- end -}}
{{- if not (gt (int .Values.hub.github.app.installId) 0) -}}
{{- fail "hub.github.app.installId is required (numeric, non-zero). It's the installation ID for the App on your org or repo." -}}
{{- end -}}
{{- if not .Values.hub.github.app.privateKey.secretName -}}
{{- fail "hub.github.app.privateKey.secretName is required. Create a Kubernetes secret holding the App's private-key PEM." -}}
{{- end -}}
{{- if not .Values.hub.github.app.owner -}}
{{- fail "hub.github.app.owner is required (chart >= 3.0.0). It's the GitHub org or user the App is installed on. Operators upgrading from chart < 3.0.0 must set this; the Hub now requires HUB_GITHUB_APP_OWNER to route webhooks." -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate the multi-App config (hub.github.apps + hub.github.appsSecret).
Called from lunar.githubAuthCheck when apps is non-empty.
*/}}
{{- define "lunar.githubAppsCheck" -}}
{{- if not .Values.hub.github.appsSecret.secretName -}}
{{- fail "hub.github.appsSecret.secretName is required when hub.github.apps is set. Create a Kubernetes secret with one PEM key per entry, named '<lowercase-owner>.pem'." -}}
{{- end -}}
{{- $seen := dict -}}
{{- range $i, $app := .Values.hub.github.apps -}}
{{- if not $app.owner -}}
{{- fail (printf "hub.github.apps[%d].owner is required" $i) -}}
{{- end -}}
{{- if not (gt (int $app.appId) 0) -}}
{{- fail (printf "hub.github.apps[%d] (%s): appId is required (numeric, non-zero)" $i $app.owner) -}}
{{- end -}}
{{- if not (gt (int $app.installId) 0) -}}
{{- fail (printf "hub.github.apps[%d] (%s): installId is required (numeric, non-zero)" $i $app.owner) -}}
{{- end -}}
{{- $key := lower $app.owner -}}
{{- if hasKey $seen $key -}}
{{- fail (printf "hub.github.apps: duplicate owner %q (case-insensitive)" $app.owner) -}}
{{- end -}}
{{- $_ := set $seen $key true -}}
{{- end -}}
{{- end }}

{{/*
Render the HUB_GITHUB_APPS JSON env value from hub.github.apps. Each
entry's private_key_path is derived from <lowercase-owner>.pem under
the Secret mountPath /secrets/github-apps. Used by hub-deployment.yaml.
*/}}
{{- define "lunar.githubAppsJSON" -}}
{{- $entries := list -}}
{{- range .Values.hub.github.apps -}}
{{- $entries = append $entries (dict
    "owner" .owner
    "app_id" (.appId | int64)
    "private_key_path" (printf "/secrets/github-apps/%s.pem" (lower .owner))
    "install_id" (.installId | int64)
) -}}
{{- end -}}
{{- $entries | toJson -}}
{{- end }}

{{/*
Fail fast when licence mount configuration is invalid.
*/}}
{{- define "lunar.hubLicenceCheck" -}}
{{- if not .Values.hub.licence.secretName -}}
{{- fail "hub.licence.secretName is required. Create a Kubernetes secret containing the signed hub licence JWT." -}}
{{- end -}}
{{- if not .Values.hub.licence.secretKey -}}
{{- fail "hub.licence.secretKey is required." -}}
{{- end -}}
{{- if not .Values.hub.licence.filePath -}}
{{- fail "hub.licence.filePath is required." -}}
{{- end -}}
{{- end }}

{{/*
Resolved name for the chart-managed Hub auth-token secret.
Honors hub.auth.secretName when set; otherwise derives from the release.
*/}}
{{- define "lunar.hubAuthSecretName" -}}
{{- .Values.hub.auth.secretName | default (printf "%s-auth-token" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed GitHub webhook secret.
*/}}
{{- define "lunar.hubWebhookSecretName" -}}
{{- .Values.hub.github.webhookSecret.secretName | default (printf "%s-github-webhook" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed Grafana admin secret.
*/}}
{{- define "lunar.grafanaAdminSecretName" -}}
{{- .Values.grafana.admin.secretName | default (printf "%s-grafana-admin" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
In-cluster DNS name for the Hub service, in `<svc>.<ns>.svc.<clusterDomain>`
form so it resolves from any namespace (the operator's scriptNamespace, in
particular). Callers that need to honor a per-component override should do
`default (include "lunar.hubHost" .) .Values.<component>.hubHost`.
*/}}
{{- define "lunar.hubHost" -}}
{{- printf "%s-hub.%s.svc.%s" (include "lunar.fullname" .) .Release.Namespace .Values.clusterDomain -}}
{{- end }}
