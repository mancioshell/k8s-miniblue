# workload-identity (Azure Workload Identity webhook)

Installs the official [`azure-workload-identity`](https://azure.github.io/azure-workload-identity/)
mutating admission webhook on the local k3s cluster via a pinned `helm_release`.

The webhook mutates any pod whose ServiceAccount/pod template carries the
`azure.workload.identity/use: "true"` label (set by the service chart, T018):

- projects a ServiceAccount token with audience `api://AzureADTokenExchange`
- injects `AZURE_AUTHORITY_HOST`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and
  `AZURE_FEDERATED_TOKEN_FILE` so the Azure SDK can exchange the projected token
  for an access token.

The default `AZURE_AUTHORITY_HOST` (`https://login.microsoftonline.com/`) is kept
as-is: the `cluster-wiring` CoreDNS override resolves that host to miniblue, so the
token exchange transparently reaches the emulator (no client secrets, FR-013 / R5).

| Input | Default | Required | Notes |
|-------|---------|----------|-------|
| `kubeconfig_path` | — | yes | AKS admin kubeconfig from `scripts/startup.sh`. |
| `tenant_id` | — | yes | Stamped into `AZURE_TENANT_ID` on mutated pods. |
| `namespace` | `azure-workload-identity-system` | no | Webhook namespace. |
| `chart_version` | `1.3.0` | no | Pinned chart version (see `versions.md`). |
