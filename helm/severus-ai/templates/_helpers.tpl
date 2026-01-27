{{- define "severus-ai.name" -}}
severus-ai
{{- end -}}

{{- define "severus-ai.fullname" -}}
{{ include "severus-ai.name" . }}
{{- end -}}
