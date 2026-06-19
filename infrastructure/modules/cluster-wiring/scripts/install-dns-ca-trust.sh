#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install-dns-ca-trust.sh — slim cluster wiring for the canonical-host model.
#
# After the KV URL-rewrite proxy and the IMDS DNAT were removed, the cluster only
# needs two things so the OFFICIAL Secrets Store CSI provider-azure + the
# azure-workload-identity flow can reach miniblue:
#   - CoreDNS overrides so the canonical Azure hosts resolve to miniblue (on the host):
#       *.vault.azure.net, login.microsoftonline.com, login.windows.net, sts.windows.net
#   - a CA ConfigMap (miniblue-kv-ca) so the provider trusts miniblue's self-signed TLS.
#
# miniblue serves the Key Vault data-plane AND the AAD authority hosts on ONE
# host-routed HTTPS listener, published on the host port 443 (see startup.sh), so a
# single A record per host pointing at the host gateway is enough — no node-side
# proxy, no cert generation, no iptables DNAT.
#
# Re-runnable. The shared-mount fix the CSI driver needs is preserved.
# Invoked by the `cluster-wiring` Terraform module (null_resource local-exec).
# Env: KUBECONFIG, AKS_CONTAINER_FILTER, MINIBLUE_CA_PATH.
# -----------------------------------------------------------------------------
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${MINIBLUE_CA_PATH:?path to miniblue CA pem is required}"
filter="${AKS_CONTAINER_FILTER:-miniblue-aks-}"
ns="kube-system"

[[ -f "${MINIBLUE_CA_PATH}" ]] || { echo "miniblue CA not found: ${MINIBLUE_CA_PATH}" >&2; exit 1; }

# Canonical hosts that must resolve to miniblue.
kv_suffix="vault.azure.net"
authority_hosts=(login.microsoftonline.com login.windows.net sts.windows.net)

# --- discover the live k3s node container + host gateway ---------------------
k3s_container="$(docker ps --filter "name=${filter}" --format '{{.Names}}' | head -n1)"
[[ -n "${k3s_container}" ]] || { echo "no running ${filter}* (k3s) container" >&2; exit 1; }

host_gw="$(MSYS_NO_PATHCONV=1 docker exec "${k3s_container}" sh -c "ip route | awk '/default/ {print \$3}'" | tr -d '\r')"
[[ -n "${host_gw}" ]] || { echo "could not determine host gateway inside k3s" >&2; exit 1; }
echo "k3s node container      : ${k3s_container}" >&2
echo "host gateway (miniblue) : ${host_gw}" >&2

# --- CA trust: miniblue's self-signed CA -> miniblue-kv-ca ConfigMap ---------
echo "applying miniblue CA trust ConfigMap (miniblue-kv-ca)" >&2
kubectl -n "${ns}" create configmap miniblue-kv-ca \
  --from-file=ca-certificates.crt="${MINIBLUE_CA_PATH}" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- CoreDNS overrides: canonical hosts -> host_gw ---------------------------
echo "applying CoreDNS overrides (canonical Azure hosts -> ${host_gw})" >&2
authority_templates=""
for h in "${authority_hosts[@]}"; do
  esc="${h//./\\.}"
  authority_templates+="
    template IN A ${h} {
      match ^${esc}\.\$
      answer \"{{ .Name }} 60 IN A ${host_gw}\"
      fallthrough
    }"
done
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
      answer "{{ .Name }} 60 IN A ${host_gw}"
      fallthrough
    }${authority_templates}
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

echo "slim cluster wiring applied (DNS + CA trust only; no proxy, no DNAT, no cert-gen)." >&2
