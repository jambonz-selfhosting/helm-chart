{{/*
Common labels
*/}}

{{- define "common.labels" -}} 
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "common.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name -}}
{{- end -}}

{{/*
Hostname helpers — all derived from baseUrl
*/}}
{{- define "jambonz.baseUrl" -}}
{{- required "baseUrl (e.g. jambonz.example.com) is required" .Values.baseUrl -}}
{{- end -}}

{{- define "jambonz.webappHostname" -}}
{{- include "jambonz.baseUrl" . -}}
{{- end -}}

{{- define "jambonz.apiHostname" -}}
{{- printf "api.%s" (include "jambonz.baseUrl" .) -}}
{{- end -}}

{{- define "jambonz.grafanaHostname" -}}
{{- printf "grafana.%s" (include "jambonz.baseUrl" .) -}}
{{- end -}}

{{- define "jambonz.homerHostname" -}}
{{- printf "homer.%s" (include "jambonz.baseUrl" .) -}}
{{- end -}}