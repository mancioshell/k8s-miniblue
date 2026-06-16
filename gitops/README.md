# gitops/ — ArgoCD source of truth

This directory holds the desired state that ArgoCD's repo-server watches. The GitOps repo is
**this monorepo** (`mancioshell/k8s-miniblue`): ArgoCD's root app reads `gitops/local/argocd-apps/` (path
`gitops/local/argocd-apps`) and the generated multi-source apps read `$values/gitops/local/values/<service>/`.
ArgoCD cannot reach a purely on-disk folder, so the desired state must be pushed to the Git
remote (research D4).

```text
gitops/
└── local/                       # one sub-tree per environment
    ├── argocd-apps/
    │   └── applicationset.yaml  # ONE ApplicationSet that renders an Application per service
    ├── shared-charts/
    │   └── service-chart-template/  # the shared, generic Helm chart (published to OCI)
    └── values/                  # per-service Helm value overrides (the $values source)
        ├── service-a/values.yaml
        └── service-b/values.yaml
```

## ApplicationSet + multi-source pattern (chart from OCI + values from Git)

Instead of one hand-written `Application` per service, a single **`ApplicationSet`**
(`local/argocd-apps/applicationset.yaml`) generates them. Its **git directory generator** auto-discovers
services from the `gitops/local/values/<service>/` folders in this repo, so **adding a service = add
`gitops/local/values/<service>/values.yaml` and push** — no manifest edit. Each generated `Application`
declares **two sources**:

1. the **shared, generic** Helm chart `service-chart-template`, pulled from the **OCI** Helm
   registry (`ghcr.io/<owner>/charts`) at a pinned `targetRevision`;
2. **this Git repo** as the `$values` source, supplying the per-service overrides via
   `helm.valueFiles: [$values/gitops/local/values/<service>/values.yaml]`.

The container **image** is pulled from `ghcr.io` by the kubelet using the `ghcr-pull`
`imagePullSecret` (created per app namespace by the `cluster-wiring` module). The chart bytes
never live in Git; only the `ApplicationSet` and the value overrides do.

> The chart `targetRevision` is shared by all services (one generic chart by design): bumping
> it in `applicationset.yaml` rolls every service. For per-service chart versions, switch the
> generator to a `list` generator with a `chartVersion` element per service.

## Push-driven auto-sync flow

1. Publish a new image (run the `build-publish.yml` GitHub Action with `service` + `version`)
   and/or a new chart revision (run the `publish-chart.yml` action with `version`) to `ghcr.io`.
2. Bump the redeploy trigger and **commit + push** the monorepo:
   - new chart revision → bump the chart source `targetRevision` in `gitops/local/argocd-apps/applicationset.yaml`;
   - new image / config → edit `gitops/local/values/<service>/values.yaml` (e.g. `image.tag`);
   - **new service** → just add `gitops/local/values/<service>/values.yaml` (the ApplicationSet generates it).

   ```bash
   git add gitops/local/argocd-apps/applicationset.yaml gitops/local/values/
   git commit -m "bump <service> to <version>"
   git push
   ```

3. ArgoCD detects the pushed commit (repo polling, default ~3 min, and/or webhook) and
   auto-syncs (self-heal + prune) — no manual `kubectl`/cluster action (FR-009, FR-010).

> Never commit secret values here (FR-012) — only Key Vault references in `values/`.

## Remote setup (one-time)

The GitOps repo is **this monorepo**. Push it to the remote and point ArgoCD at it:

```bash
git remote add origin https://github.com/<you>/k8s-miniblue.git   # if not already set
git add . && git commit -m "gitops source"
git push -u origin main
```

Set the same remote as `GITOPS_REPO_URL` (the ArgoCD root-app `repoURL`, path `gitops/local/argocd-apps`; see
`infrastructure/modules/argocd`); the OCI chart repo and its pull credentials are wired there too.
