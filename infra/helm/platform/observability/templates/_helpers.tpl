{{/*
The container security context for every first-party workload that this chart
renders. It is the same in all four. It is written once here, because a copy that
drifts makes a namespace stop admitting pods. The failure then lands on the next
pod that rolls, and not on the edit that caused it.

`readOnlyRootFilesystem` is not part of the `restricted` Pod Security Standard.
But it is the one item here that limits what a compromised process can do, and
the misconfig gate of `ci:scan` requires it, as KSV-0014. It works here, because
all four write only into mounts, and each mount is an emptyDir:
- Alloy writes to its storage path.
- Prometheus and Pyroscope write to their data dirs.
- The cluster collector writes nothing.
An emptyDir stays writable under a read-only root.

The pod half, runAsNonRoot, runAsUser, and seccompProfile, stays inline in each
template. Each image ships with a different UID, and the reason for a number
belongs next to the image that it applies to.
*/}}
{{- define "observability.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}
