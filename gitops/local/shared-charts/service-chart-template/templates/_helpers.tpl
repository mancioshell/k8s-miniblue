{{- define "service-chart-template.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}
{{- define "service-chart-template.labels" -}}
app.kubernetes.io/name: {{ include "service-chart-template.name" . }}
app.kubernetes.io/managed-by: argocd
{{- end -}}
