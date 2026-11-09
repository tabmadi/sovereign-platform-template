{{- define "design-preview.namespace" -}}
design-pr-{{ required "pr is required" .Values.pr }}
{{- end -}}
