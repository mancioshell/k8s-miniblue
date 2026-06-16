# -----------------------------------------------------------------------
# kubeconfig — turn miniblue's AKS into a HOST-reachable kubeconfig, exposed
# as a Terraform output and written to disk. Depends on the aks unit; downstream
# units (cluster-wiring, argocd, secrets-csi) consume kubeconfig_path.
#
# The server-port rewrite needs the random docker-published port (docker inspect),
# so the extraction is a null_resource local-exec; data.local_file then re-reads
# the written file to surface its content as a first-class Terraform value.
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.5.2"
    }
  }
}

resource "null_resource" "extract" {
  # Re-extract on every apply: the mapped API port can change if the AKS/k3s
  # container was recreated. Idempotent — the script just rewrites the file.
  triggers = {
    aks_cluster_id = var.aks_cluster_id
    always_run     = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/extract-kubeconfig.sh"
    environment = {
      KUBECONFIG_OUT       = var.kubeconfig_path
      AKS_CONTAINER_FILTER = var.aks_container_filter
    }
  }
}

data "local_file" "kubeconfig" {
  filename   = var.kubeconfig_path
  depends_on = [null_resource.extract]
}
