#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install-kv-proxy.sh — Option A translation shim so the OFFICIAL Secrets Store CSI
# provider-azure can read secrets from miniblue. Installs on the k3s cluster:
#   - a hostNetwork DaemonSet (miniblue-kv-proxy) on node :80 (IMDS) + :443 (KV)
#   - a self-signed CA + server cert for *.vault.azure.net (TLS secret)
#   - a CoreDNS override (*.vault.azure.net -> NODE_IP)
#   - an iptables DNAT (169.254.169.254:80 -> NODE_IP:80) so IMDS hits the proxy
#   - a CA ConfigMap (miniblue-kv-ca) the provider DaemonSet trusts
# Re-runnable. Independent of the imagePullSecret step (no k3s restart involved).
#
# Invoked by the `cluster-wiring` Terraform module (null_resource local-exec).
# Env: KUBECONFIG, AKS_CONTAINER_FILTER, MINIBLUE_DATA_PORT, PROXY_PY, KV_CA_OUT.
# -----------------------------------------------------------------------------
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${MINIBLUE_DATA_PORT:?required}"
: "${PROXY_PY:?path to proxy.py is required}"
filter="${AKS_CONTAINER_FILTER:-miniblue-aks-}"
ca_out="${KV_CA_OUT:-${PWD}/.miniblue-kv-ca.pem}"
ns="kube-system"
kv_suffix="vault.azure.net"

[[ -f "${PROXY_PY}" ]] || { echo "proxy.py not found: ${PROXY_PY}" >&2; exit 1; }

# --- discover the live k3s node container, its node IP and host gateway -------
k3s_container="$(docker ps --filter "name=${filter}" --format '{{.Names}}' | head -n1)"
[[ -n "${k3s_container}" ]] || { echo "no running ${filter}* (k3s) container" >&2; exit 1; }

node_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${k3s_container}")"
[[ -n "${node_ip}" ]] || { echo "could not determine k3s node IP" >&2; exit 1; }

host_gw="$(MSYS_NO_PATHCONV=1 docker exec "${k3s_container}" sh -c "ip route | awk '/default/ {print \$3}'" | tr -d '\r')"
[[ -n "${host_gw}" ]] || { echo "could not determine host gateway inside k3s" >&2; exit 1; }
miniblue_kv_base="http://${host_gw}:${MINIBLUE_DATA_PORT}"

echo "k3s node container : ${k3s_container}" >&2
echo "node IP            : ${node_ip}" >&2
echo "miniblue KV base   : ${miniblue_kv_base}" >&2

# --- generate CA + server cert for *.vault.azure.net -------------------------
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

echo "generating self-signed CA + server cert for *.${kv_suffix}" >&2
# NOTE: leading // in -subj avoids Git-Bash/MSYS converting it to a Windows path.
openssl genrsa -out "${work}/ca.key" 2048 >/dev/null 2>&1
openssl req -x509 -new -nodes -key "${work}/ca.key" -sha256 -days 3650 \
  -subj "//CN=miniblue-kv-ca" -out "${work}/ca.crt" >/dev/null 2>&1

openssl genrsa -out "${work}/tls.key" 2048 >/dev/null 2>&1
openssl req -new -key "${work}/tls.key" \
  -subj "//CN=kv-mb-local.${kv_suffix}" -out "${work}/tls.csr" >/dev/null 2>&1
cat > "${work}/ext.cnf" <<EOF
subjectAltName=DNS:*.${kv_suffix},DNS:${kv_suffix},DNS:kv-mb-local.${kv_suffix}
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -in "${work}/tls.csr" -CA "${work}/ca.crt" -CAkey "${work}/ca.key" \
  -CAcreateserial -days 825 -sha256 -extfile "${work}/ext.cnf" \
  -out "${work}/tls.crt" >/dev/null 2>&1

mkdir -p "$(dirname "${ca_out}")"
cp "${work}/ca.crt" "${ca_out}"
echo "CA written to ${ca_out}" >&2

# --- apply k8s objects -------------------------------------------------------
echo "applying proxy code / TLS / CA objects" >&2
kubectl -n "${ns}" create configmap miniblue-kv-proxy-code \
  --from-file=proxy.py="${PROXY_PY}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${ns}" create secret tls miniblue-kv-proxy-tls \
  --cert="${work}/tls.crt" --key="${work}/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${ns}" create configmap miniblue-kv-ca \
  --from-file=ca-certificates.crt="${work}/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "applying hostNetwork proxy DaemonSet" >&2
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: miniblue-kv-proxy
  namespace: ${ns}
  labels: { app: miniblue-kv-proxy }
spec:
  selector:
    matchLabels: { app: miniblue-kv-proxy }
  template:
    metadata:
      labels: { app: miniblue-kv-proxy }
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      tolerations:
        - operator: Exists
      containers:
        - name: proxy
          image: python:3.12-alpine
          command: ["python3", "/app/proxy.py"]
          env:
            - { name: MINIBLUE_KV_BASE, value: "${miniblue_kv_base}" }
            - { name: HTTP_PORT,  value: "80" }
            - { name: HTTPS_PORT, value: "443" }
            - { name: TLS_CERT_FILE, value: "/tls/tls.crt" }
            - { name: TLS_KEY_FILE,  value: "/tls/tls.key" }
          ports:
            - { containerPort: 80,  hostPort: 80,  name: imds }
            - { containerPort: 443, hostPort: 443, name: keyvault }
          securityContext:
            runAsUser: 0
            capabilities:
              add: ["NET_BIND_SERVICE"]
          readinessProbe:
            httpGet: { path: /healthz, port: 443, scheme: HTTPS }
            initialDelaySeconds: 3
            periodSeconds: 5
          volumeMounts:
            - { name: code, mountPath: /app }
            - { name: tls,  mountPath: /tls, readOnly: true }
      volumes:
        - name: code
          configMap: { name: miniblue-kv-proxy-code }
        - name: tls
          secret: { secretName: miniblue-kv-proxy-tls }
EOF

# --- CoreDNS override: *.vault.azure.net -> NODE_IP --------------------------
echo "applying CoreDNS override for *.${kv_suffix} -> ${node_ip}" >&2
kubectl -n "${ns}" apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: ${ns}
data:
  miniblue-kv.override: |
    template IN A ${kv_suffix} {
      match (.*)\.${kv_suffix//./\\.}\.\$
      answer "{{ .Name }} 60 IN A ${node_ip}"
      fallthrough
    }
EOF
kubectl -n "${ns}" rollout restart deploy/coredns >/dev/null 2>&1 || true

# --- ensure kubelet root is a shared mount (CSI driver needs Bidirectional) ---
echo "ensuring shared mount propagation for the CSI driver" >&2
MSYS_NO_PATHCONV=1 docker exec "${k3s_container}" sh -c '
  while grep -q " /var/lib/kubelet " /proc/1/mountinfo && \
        [ "$(grep -c " /var/lib/kubelet " /proc/1/mountinfo)" -gt 1 ]; do
    umount -l /var/lib/kubelet 2>/dev/null || break
  done
  mount --make-rshared / 2>/dev/null || true
' || echo "warn: could not adjust mount propagation (CSI driver may need a manual fix)" >&2

# --- iptables DNAT: 169.254.169.254:80 -> NODE_IP:80 (inside k3s node) --------
echo "installing IMDS DNAT rule inside ${k3s_container}" >&2
for chain in PREROUTING OUTPUT; do
  MSYS_NO_PATHCONV=1 docker exec "${k3s_container}" \
    iptables -t nat -C "${chain}" -d 169.254.169.254/32 -p tcp --dport 80 \
      -j DNAT --to-destination "${node_ip}:80" 2>/dev/null \
  || MSYS_NO_PATHCONV=1 docker exec "${k3s_container}" \
    iptables -t nat -A "${chain}" -d 169.254.169.254/32 -p tcp --dport 80 \
      -j DNAT --to-destination "${node_ip}:80"
done
echo "DNAT installed (169.254.169.254:80 -> ${node_ip}:80)" >&2

# --- wait for proxy readiness ------------------------------------------------
echo "waiting for miniblue-kv-proxy to become ready" >&2
kubectl -n "${ns}" rollout status ds/miniblue-kv-proxy --timeout=120s

echo "miniblue-kv-proxy installed. CA for provider trust: ${ca_out}" >&2
