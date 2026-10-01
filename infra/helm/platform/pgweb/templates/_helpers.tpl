{{/*
The DSN, and where its password comes from.

Every deployed environment keeps the read-only role's password in a Secret, per
ADR-0202. Such an environment cannot put the DSN in a values file, because the
DSN CONTAINS the password. So the URL is built from parts here. The password
arrives as an env var, and both containers below expand it.

`databaseUrl` stays for the local tier. Its read-only password is a throwaway
value, committed next to it. An empty one is not a default. pg_isready reads an
empty `-d` as a connection over the local socket. The init container then waits
forever on `/var/run/postgresql:5432`. The message does not say that Postgres is
at a different place.
*/}}
{{- define "pgweb.dsnEnv" -}}
{{- $pg := .Values.pgweb -}}
{{- if $pg.databaseUrl }}
- { name: PGWEB_DATABASE_URL, value: {{ $pg.databaseUrl | quote }} }
{{- else }}
{{- $db := required "pgweb: set databaseUrl, or database.host and database.name" $pg.database }}
- name: PGWEB_DB_PASSWORD
  valueFrom:
    secretKeyRef: { name: {{ $db.passwordSecret }}, key: {{ $db.passwordKey }} }
- name: PGWEB_DATABASE_URL
  value: "postgres://{{ $db.user }}:$(PGWEB_DB_PASSWORD)@{{ required "pgweb.database.host" $db.host }}:{{ $db.port }}/{{ required "pgweb.database.name" $db.name }}?sslmode={{ $db.sslMode }}"
{{- end }}
{{- end -}}
