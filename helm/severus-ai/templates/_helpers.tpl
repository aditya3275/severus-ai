{{- define "severus-ai.name" -}}
severus-ai
{{- end }}

{{- define "severus-ai.fullname" -}}
severus-ai
{{- end }}

{{- define "severus-ai.selectorLabels" -}}
app.kubernetes.io/name: {{ include "severus-ai.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "severus-ai.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "severus-ai.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
