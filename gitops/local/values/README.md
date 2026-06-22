# GitOps service values

The ArgoCD `ApplicationSet` (`../argocd-apps/applicationset.yaml`) uses a **git directory
generator** over `gitops/local/values/*`. It renders **one `Application` per
subdirectory** found here — the *presence of the directory* is what makes a service exist
and get deployed (namespace + workload). Commenting out the contents of a `values.yaml`
does **not** disable it: the directory is still discovered and the shared chart renders
with its defaults.

So the deploy model is presence-based:

- **Deploy a service** → add `gitops/local/values/<service>/values.yaml` with real content
  and commit/push to `main`. ArgoCD generates its `Application`, creates the `<service>`
  namespace (`CreateNamespace=true`) and syncs the workload.
- **Remove a service** → delete its `values/<service>/` directory and commit/push. The
  ApplicationSet (`prune: true`) removes the generated `Application` and its resources.
  Note: ArgoCD does **not** delete a namespace it created via `CreateNamespace=true`, so
  remove `<service>` namespaces manually if needed:
  `kubectl delete ns <service>`.

> This `README.md` is a plain file (not a directory), so the directory generator ignores
> it — it will never be deployed.

## Example `values/<service>/values.yaml`

Per-service overrides consumed by the SHARED chart (`service-chart-template`) as the
`$values` source. **No secret VALUES here, only references (FR-012).**

```yaml
nameOverride: service-a

image:
  repository: ghcr.io/mancioshell/service-a
  tag: "1.0.0"

# imagePullSecret created in this namespace by the cluster-wiring module.
imagePullSecrets:
  - name: ghcr-pull

replicaCount: 2

secrets:
  enabled: true
  keyvaultName: kv-mb-local
  managedIdentityClientId: "22222222-2222-2222-2222-222222222222"   # UAMI client_id (managed-identity output)
  tenantId: "11111111-1111-1111-1111-111111111111"
  objects:
    - name: app-greeting-secret
      env: APP_GREETING_SECRET
  syncK8sSecretName: service-a-secrets
```
