{{/* The validation action of a policy: Enforce denies, and Audit records a PolicyReport and admits. */}}
{{- define "policies.action" -}}
{{- if eq .Values.policies.validationFailureAction "Enforce" }}Deny{{ else }}Audit{{ end -}}
{{- end }}

{{/* Every image of a pod, from all three container lists, as one CEL list. */}}
{{- define "policies.podImages" -}}
(object.spec.containers + object.spec.?initContainers.orValue([]) + object.spec.?ephemeralContainers.orValue([])).map(c, c.image)
{{- end }}

{{/* The first-party prefix with its trailing wildcard removed, as a CEL string. */}}
{{- define "policies.prefix" -}}
{{ trimSuffix "*" .Values.policies.imagePrefix | toJson }}
{{- end }}

{{/* The signature check that both image policies share, per ADR-0113. */}}
{{- define "policies.signature" -}}
{{- with .Values.policies.registrySecret }}
# The signature is a referrer in the same private registry that the image comes from. Kyverno reads it with the same
# credential, from a Secret in its own namespace.
credentials:
  secrets: [{{ . | quote }}]
{{- end }}
validationConfigurations:
  mutateDigest: true
  required: true
  verifyDigest: true
attestors:
  - name: platform
    cosign:
      key:
        data: |-
{{ .Values.policies.publicKey | trim | indent 10 }}
        # The hash is pinned. A policy that accepts any algorithm that the signature claims accepts a downgrade.
        hashAlgorithm: sha256
      # No transparency log, on purpose, in both directions. ADR-0113 chose a key pair over keyless, because the only
      # verifier here is our own admission controller. Keyless gives the trust root to an outside party.
      ctlog:
        insecureIgnoreTlog: true
        insecureIgnoreSCT: true
variables:
  - name: prefix
    expression: {{ include "policies.prefix" . | quote }}
validations:
  - expression: >-
      (images.containers + images.?initContainers.orValue([]) + images.?ephemeralContainers.orValue([]))
        .filter(image, image.startsWith(variables.prefix))
        .all(image, verifyImageSignatures(image, [attestors.platform]) > 0)
    message: >-
      A first-party image must carry the signature of the platform key, per ADR-0113.
{{- end }}
