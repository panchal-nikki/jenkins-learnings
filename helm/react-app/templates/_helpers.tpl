{{/*
  _helpers.tpl — Reusable template snippets
  
  These named templates (partials) are called with `include`
  throughout other templates to keep things DRY.
  
  Usage: {{ include "react-app.fullname" . }}
*/}}

{{/* Expand the chart name */}}
{{- define "react-app.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
  Create a default fully qualified app name.
  If Release.Name already contains the chart name, avoid duplication.
  e.g. release "my-release" → "my-release-react-app"
       release "react-app"  → "react-app"
*/}}
{{- define "react-app.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Chart label: chart-name-chart-version */}}
{{- define "react-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
  Common labels — applied to every resource.
  Helm best-practice labels for consistency & GitOps tools.
*/}}
{{- define "react-app.labels" -}}
helm.sh/chart: {{ include "react-app.chart" . }}
{{ include "react-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
  Selector labels — used to match pods to Services/Deployments.
  Keep these STABLE; changing them requires deleting the Deployment.
*/}}
{{- define "react-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "react-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
