# k8s-miniblue — Local AKS + ArgoCD GitOps demo

A fully local, reproducible GitOps pipeline on the [miniblue](https://miniblue.io) Azure
emulator: Terraform/Terragrunt provision Azure objects **including a real AKS cluster**
(miniblue `AKS_BACKEND=k3s`), and ArgoCD delivers Spring Boot services with a **multi-source**
pattern — a **shared Helm chart pulled from GHCR (OCI)** overlaid with **per-service values
from Git** — while secrets are injected at runtime from Key Vault via the Secrets Store CSI
driver.

> Feature spec & design: [specs/001-aks-gitops-springboot/](specs/001-aks-gitops-springboot/).
> Pinned versions: [versions.md](versions.md).

## Prerequisites

- Docker (running), Terraform `>= 1.10.3`, Terragrunt, Helm 3, kubectl, git, python (for JSON helpers)
- A GitHub repo for the GitOps source (public, or private with `GITOPS_REPO_TOKEN`)
- A **classic GitHub PAT** with `read:packages` (+ `write:packages` to publish) for `ghcr.io` —
  images and the shared chart live in **private** GHCR packages; provide it as `GHCR_TOKEN`
- miniblue `:full` image (or host binary) — the real AKS backend needs the docker CLI
- Git-Bash on Windows (the scripts use `MSYS_NO_PATHCONV=1` / `cygpath`); on Linux/macOS they run as-is

## Architecture

```text
Terragrunt ─► miniblue ARM ─► RG, Managed Identity, ACR, Key Vault, AKS(real k3s container)
                                                               │ admin kubeconfig
Terraform modules ────────────────────────────────────────────┴─► ArgoCD + Secrets Store CSI + cluster-wiring
GHCR (ghcr.io) ─► image bytes ──────────(imagePullSecret ghcr-pull)──► kubelet pulls image
GHCR (ghcr.io) ─► shared chart (OCI) ┐
Git repo ($values) ─► per-service values ┴─► ArgoCD ApplicationSet ─► Application/service ─► auto-sync
Key Vault secret ─► CSI (UAMI via IMDS, miniblue-kv-proxy) ──────────► pod env at runtime
```

- **Multi-source delivery**: each ArgoCD `Application` has two sources — the **shared, generic**
  chart `service-chart-template` pulled from **OCI** (`ghcr.io/<owner>/charts`) and **this Git repo**
  as the `$values` source (`valueFiles: [$values/gitops/local/values/<service>/values.yaml]`). One chart, many
  services; per-service config lives only in Git.
- **Private GHCR pull**: the container **image** is pulled from `ghcr.io` using the `ghcr-pull`
  `imagePullSecret`, created per app namespace by the `cluster-wiring` module from
  `GHCR_USERNAME`/`GHCR_TOKEN`. ArgoCD gets the same credentials as a private OCI Helm repo.

## Runbook (clean checkout → running app, end-to-end test)

> One-time prep: push **this monorepo** to a GitHub repo — ArgoCD's root app reads `gitops/local/argocd-apps/`
> (path `gitops/local/argocd-apps`) and the generated multi-source apps read `$values/gitops/local/values/`. Put the
> repo URL in `GITOPS_REPO_URL` inside a gitignored `.env` (copy from `.env.example`). The shared
> chart is pulled from GHCR (OCI), not Git. The repo can be public or private (private needs
> `GITOPS_REPO_TOKEN`). GHCR is private, so set `GHCR_TOKEN` too.

A full bring-up is two scripts: publish the artifacts, then `startup.sh` (one command that
brings up the platform substrate — miniblue/real AKS — and the whole Terraform stack,
including the mandatory image-pull-secret → KV-proxy wiring). GitOps is part of the same
apply: `startup.sh` enables the ArgoCD root app when `GITOPS_REPO_URL` is set (via `.env`).
Terraform also generates a random Key Vault secret and seeds it into miniblue during the
apply — no manual seeding.

```bash
cd /c/git/k8s-miniblue

# Publish the artifacts to ghcr.io FIRST so ArgoCD finds them when it syncs. These run as
# manually-triggered GitHub Actions (Actions tab → Run workflow, or the gh CLI below).
# They authenticate with the built-in GITHUB_TOKEN — no PAT needed for publishing.
gh workflow run build-publish.yml -f service=service-a -f version=1.0.0
gh workflow run build-publish.yml -f service=service-b   -f version=1.0.0
gh workflow run publish-chart.yml -f version=1.1.0

# miniblue (real AKS/k3s) + tf apply (+random KV secret) + creds + cluster-wiring
# (pull secret + KV/IMDS shim) AND GitOps wiring, in order. GITOPS_REPO_URL (and
# GITOPS_REPO_TOKEN for a private repo) plus GHCR_TOKEN (to PULL the private packages)
# come from the gitignored .env (copy .env.example to .env and fill it in).
scripts/startup.sh
export KUBECONFIG="$PWD/kubeconfig"
scripts/verify.sh
```

> To re-point GitOps elsewhere later (or toggle it off), change `GITOPS_REPO_URL`
> (and `GITOPS_REPO_REVISION`) in `.env` and re-run `scripts/startup.sh` — it is
> idempotent and reconciles the root app to the new repo/revision.


After a few minutes the ArgoCD `Application`s (`root`, `service-a`, `service-b`)
report `Synced` + `Healthy`, each pod runs `ghcr.io/<owner>/<service>:<tag>` (pulled with the
`ghcr-pull` secret), and `APP_GREETING_SECRET` resolves to the seeded Key Vault value.

```bash
# Reach a service (k3s disables Traefik — use port-forward)
kubectl -n service-a port-forward deploy/service-a 8080:8080 &
curl localhost:8080/   # {"version":"1.0.0","app":"service-a"}
```

### Release a new version (the GitOps loop)

```bash
# A) New image only (most common): build+push the service image, then point values at it.
gh workflow run build-publish.yml -f service=service-a -f version=1.1.0
#    edit gitops/local/values/service-a/values.yaml -> image.tag: "1.1.0"
git add gitops/local/values/service-a/values.yaml && \
  git commit -m "service-a image 1.1.0" && git push

# B) New chart revision (affects every service): publish a new chart version, retarget the set.
gh workflow run publish-chart.yml -f version=1.2.0
#    edit gitops/local/argocd-apps/applicationset.yaml -> chart source targetRevision: 1.2.0
git add gitops/local/argocd-apps/applicationset.yaml && \
  git commit -m "shared chart 1.2.0" && git push

# ArgoCD auto-detects the pushed commit (polling ~3 min, or force: kubectl annotate
# application <service> -n argocd argocd.argoproj.io/refresh=normal --overwrite)
# and rolls the app with no manual cluster action (self-heal + prune).
```

> Re-provisioning note: a `docker restart` of the k3s container wipes runtime-only state
> (shared mount, IMDS DNAT, the in-cluster pull secret / KV-proxy wiring). Re-run
> `scripts/startup.sh` to restore them (it re-applies cluster-wiring: image pull secret then
> the KV/IMDS shim).

## Teardown

```bash
scripts/teardown.sh   # destroys Azure objects + k3s container, removes registry/miniblue + kubeconfig
```

## Repository layout

| Path | Purpose |
|------|---------|
| `infrastructure/modules/` | Reusable Terraform modules (RG, MI, ACR, KV, AKS) + platform add-ons (`argocd`, `secrets-csi`, `cluster-wiring`). |
| `infrastructure/live-k8s/local/` | Terragrunt composition for the single `local` environment (one unit + tfstate per object). |
| `apps/<service>/` | Each Spring Boot service: application code + multi-stage Dockerfile **only** (e.g. `service-a`, `service-b`). |
| `gitops/local/shared-charts/service-chart-template/` | The **one shared, generic** Helm chart reused by every service (Deployment, Service, SecretProviderClass). |
| `gitops/` | Authoring mirror of the GitOps repo ArgoCD watches: `local/argocd-apps/` (one `ApplicationSet` per environment generating an Application per service) + `local/values/` (per-service overrides). |
| `scripts/` | Idempotent runbook scripts: orchestrator `startup.sh` (miniblue + tf apply + creds + cluster-wiring + GitOps wiring); then `verify.sh`, `teardown.sh`. |
| `.github/workflows/` | Manually-triggered GitHub Actions: `build-publish.yml` (inputs: `service`, `version` — build + push a service image to ghcr.io) and `publish-chart.yml` (input: `version` — package + push the shared chart to ghcr.io OCI). Both authenticate with the built-in `GITHUB_TOKEN`. |

## Notes & known constraints

- **miniblue ACR data plane is stubbed** (research R1): the effective image + chart bytes live
  in **GHCR** (`ghcr.io`), which k3s and ArgoCD pull from directly; the ACR object is only the
  declared Azure representation. There is no local registry and no containerd mirror anymore.
- **Private GHCR packages**: images and the shared chart are **private** packages. k3s pulls the
  image with the `ghcr-pull` `imagePullSecret` (created per app namespace by the `cluster-wiring`
  module from `GHCR_USERNAME`/`GHCR_TOKEN`); ArgoCD pulls the OCI chart with the same credentials
  registered as a private Helm repo. The PAT never lands in Git — supply it via the gitignored `.env`.
- **Multi-source apps**: a single `ApplicationSet` (`local/argocd-apps/applicationset.yaml`) renders one
  multi-source Application per service — the shared chart comes from OCI and the per-service
  values from Git (`$values`). Bump `image.tag` in `local/values/<service>/` for an image roll, or the
  chart source `targetRevision` in `local/argocd-apps/applicationset.yaml` for a chart roll (all services).
- **Private GitOps repo**: the repo can be private — set `GITOPS_REPO_TOKEN` (a read-only
  GitHub PAT) in `.env` before `scripts/startup.sh`. ArgoCD stores it in a `repository` secret
  (username defaults to `git`). Leave it unset for a public repo. Never commit the token.
- **Key Vault secret is Terraform-managed + random**: the `key-vault` unit generates a random
  value (`random_password`) and seeds it into the miniblue KV data plane during `apply` (step 1)
  — no manual seeding. The value is stable across applies (regenerates only on taint). miniblue's
  data plane is in-memory, so a **miniblue** restart needs a re-seed (re-run `terraform apply`,
  e.g. via `scripts/startup.sh`); a **k3s** restart (`scripts/startup.sh`) does not affect it.
- **Workload Identity (AAD federation) is unavailable** on miniblue — pod identity uses a
  User-Assigned MI via IMDS, brokered by the `miniblue-kv-proxy` shim installed by the
  `cluster-wiring` module (TLS proxy for `*.vault.azure.net`, CoreDNS overrides, IMDS DNAT).
- **Restart wipes runtime state**: a `docker restart` of the k3s container drops the shared
  mount, IMDS DNAT, and in-cluster wiring — re-run `scripts/startup.sh` to restore them.
- k3s disables Traefik — access services via `kubectl port-forward`.
- Local Terraform state is intentional and compliant for this single, non-shared environment.
