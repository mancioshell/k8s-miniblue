# infrastructure/

Reusable Terraform **modules** and the Terragrunt **live** composition for the single `local`
environment. The cluster platform add-ons (ArgoCD, Secrets Store CSI, the miniblue KV/IMDS
shim) are now plain modules under `modules/` — there is no separate `bootstrap/` layer.

```text
infrastructure/
├── modules/        # reusable Terraform modules (target: miniblue)
│   ├── argocd/         # ArgoCD install + repo credentials (OCI chart repo + GitOps repo)
│   ├── cluster-wiring/ # imagePullSecret (ghcr-pull) + miniblue KV/IMDS proxy DaemonSet
│   ├── secrets-csi/    # Secrets Store CSI driver + Azure provider
│   └── ...             # RG, managed identity, ACR, Key Vault, AKS, kubeconfig
└── live-k8s/       # Terragrunt live config (root.hcl + local/ environment)
    └── local/          # one unit per object; one tfstate per unit
```

## Conventions

- **Formatting**: run `terraform fmt -recursive` on `infrastructure/modules`, and
  `terragrunt hclfmt` on `infrastructure/live-k8s`, before every commit. CI/local checks assume
  canonical formatting.
- **Linting**: `tflint --recursive` from the repo root (config: `.tflint.hcl`).
- **Validation gate (constitution V)**: `terraform/terragrunt validate` + `plan` MUST pass and
  be reviewed before any `apply`. Never apply without inspecting the plan.
- **Provider generation**: the azurerm provider block (with `metadata_host`, endpoint
  overrides, and fake credentials targeting miniblue) is generated once by Terragrunt in
  `live-k8s/root.hcl`. Modules MUST NOT declare a `backend` or hardcode credentials/endpoints.
  Helm/kubernetes-only units MUST NOT generate a second `provider` block.
- **State**: local state only, one `terraform.tfstate` per unit under
  `live-k8s/local/<unit>/` — compliant for this single, non-shared, local environment
  (research D6). The path is relative to the unit, so it survives directory moves.
