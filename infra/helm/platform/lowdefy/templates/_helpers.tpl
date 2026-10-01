{{/*
lowdefy.image: the admin console image reference. It uses an immutable digest
before a tag. Prod has a digest, pinned by promote-on-release. Local, dev, and
staging use a tag. It works like the service.image helper of the service chart,
per ADR-0103.
*/}}
{{- define "lowdefy.image" -}}
{{- $r := required ".Values.lowdefy.image.repository is required" .Values.lowdefy.image.repository -}}
{{- if .Values.lowdefy.image.digest -}}
{{ $r }}@{{ .Values.lowdefy.image.digest }}
{{- else -}}
{{ $r }}:{{ required ".Values.lowdefy.image.tag or .digest is required: a concrete git SHA or digest, per ADR-0101 and ADR-0103" .Values.lowdefy.image.tag }}
{{- end -}}
{{- end -}}
