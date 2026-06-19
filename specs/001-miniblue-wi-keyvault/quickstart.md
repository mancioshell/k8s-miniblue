# Quickstart: validate miniblue Workload Identity + canonical Key Vault

End-to-end validation that the modified emulator + rewired cluster deliver the feature **without**
the interception shim. Run from the repo root in Git-Bash. Details of each contract live in
[contracts/](contracts/); entity shapes in [data-model.md](data-model.md).

## Prerequisites

- Docker running; `kubectl`, `helm`, `terragrunt`, `az`/Azure SDK or `curl` available.
- The miniblue **fork** pin set (`MINIBLUE_SRC_REPO` / `MINIBLUE_SRC_REF` in `scripts/lib/common.sh`
  or `.env`) and the custom `full` image built from it.
- `KUBECONFIG=c:/git/k8s-miniblue/kubeconfig`.

## 1. Bring up the cluster (no shim)

```bash
./scripts/startup.sh
```
Expected: cluster comes up; the `cluster-wiring` step no longer installs the IMDS DNAT, the KV
URL-rewrite proxy, or per-run `*.vault.azure.net` certs; it only configures DNS overrides + CA
trust. The `azure-workload-identity` webhook is installed and Running.

## 2. Canonical Key Vault data-plane (US1 / SC-001, SC-002)

From a debug pod (or via in-cluster DNS), call the **canonical host** directly — no path rewriting:
```bash
# set a secret, then read it back on https://<vault>.vault.azure.net
curl -sS --cacert <miniblue-ca> \
  -X PUT "https://<vault>.vault.azure.net/secrets/demo?api-version=7.4" \
  -H 'Authorization: Bearer <any>' -H 'Content-Type: application/json' \
  -d '{"value":"hello"}'

curl -sS --cacert <miniblue-ca> \
  "https://<vault>.vault.azure.net/secrets/demo?api-version=7.4" -H 'Authorization: Bearer <any>'
```
Expected: `200` with `{"id":"https://<vault>.vault.azure.net/secrets/demo/...","value":"hello",...}`.

## 3. Federated identity credential as IaC (US3 / FR-009, FR-010)

```bash
cd infrastructure/live-k8s/local/<managed-identity-or-federated-unit>
terragrunt apply
```
Expected: `azurerm_user_assigned_identity` + `azurerm_federated_identity_credential` apply cleanly;
GET on the ARM paths (see [contracts/managedidentity-arm.md](contracts/managedidentity-arm.md))
returns the UAMI and the FIC with `subject = system:serviceaccount:service-a:service-a`.

## 4. Workload Identity pod auth — no IMDS (US2 / SC-003, SC-004)

```bash
kubectl -n service-a get sa service-a -o yaml      # annotated azure.workload.identity/client-id
kubectl -n service-a get pod -l app=service-a -o yaml | grep -E 'AZURE_(CLIENT_ID|TENANT_ID|FEDERATED_TOKEN_FILE|AUTHORITY_HOST)|azure-identity-token'
```
Expected: the webhook injected the projected token volume + `AZURE_*` env. The pod obtains a KV
secret; checking miniblue logs shows the token came from the **`/oauth2/v2.0/token`** federated
exchange and there were **no** calls to `/metadata/identity/oauth2/token` (IMDS).

## 5. OIDC discovery + JWKS resolves (FR-007)

```bash
curl -sS --cacert <miniblue-ca> "https://login.microsoftonline.com/<tenant>/v2.0/.well-known/openid-configuration" | jq .jwks_uri
curl -sS --cacert <miniblue-ca> "https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys"   | jq '.keys[0].kid'
```
Expected: `jwks_uri` resolves to a JWK set (no `404`); the `kid` matches the issued token header.

## 6. Services healthy end-to-end (SC-005)

```bash
KUBECONFIG=c:/git/k8s-miniblue/kubeconfig kubectl get pods -A
./scripts/verify.sh
```
Expected: `service-a` and `service-b` Running with their KV-backed secrets mounted/available via
Workload Identity.

## Pass criteria

- [ ] KV reachable on `https://<vault>.vault.azure.net/...` with no proxy/path rewrite (SC-001/002)
- [ ] Pod auth uses the federated token exchange, zero IMDS calls (SC-003/004)
- [ ] Federated credential exists as applied IaC (FR-009/010)
- [ ] OIDC `jwks_uri` resolves and matches the signing key (FR-007)
- [ ] Both services healthy; shim (DNAT + proxy + cert-gen) removed (SC-005 / FR-012)
