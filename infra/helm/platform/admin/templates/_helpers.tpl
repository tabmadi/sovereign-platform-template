{{/*
admin.image: the admin console image reference. It uses an immutable digest
before a tag. Prod has a digest, pinned by promote-on-release. Local, dev, and
staging use a tag. It works like the service.image helper of the service chart,
per ADR-0112.
*/}}
{{- define "admin.image" -}}
{{- $r := required ".Values.admin.image.repository is required" .Values.admin.image.repository -}}
{{- if .Values.admin.image.digest -}}
{{ $r }}@{{ .Values.admin.image.digest }}
{{- else -}}
{{ $r }}:{{ required ".Values.admin.image.tag or .digest is required: a concrete git SHA or digest, per ADR-0111 and ADR-0112" .Values.admin.image.tag }}
{{- end -}}
{{- end -}}
