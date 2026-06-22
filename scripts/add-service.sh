#!/usr/bin/env bash
# add-service.sh <service-name>
# Creates gitops/local/values/<name>/values.yaml and adds the service to env.hcl.
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <service-name>" >&2
  exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
ENV_HCL="$REPO_ROOT/infrastructure/live-k8s/local/env.hcl"
VALUES_DIR="$REPO_ROOT/gitops/local/values/$NAME"
VALUES_FILE="$VALUES_DIR/values.yaml"

SECRET_NAME="${NAME}-secret"
ENV_VAR="$(echo "${NAME}" | tr 'a-z-' 'A-Z_')_SECRET"

# ── 1. gitops values.yaml ────────────────────────────────────────────────────
if [[ -d "$VALUES_DIR" ]]; then
  echo "skip: $VALUES_DIR already exists"
else
  mkdir -p "$VALUES_DIR"
  cat > "$VALUES_FILE" <<YAML
nameOverride: $NAME

image:
  repository: ghcr.io/mancioshell/$NAME
  tag: "1.0.0"

imagePullSecrets:
  - name: ghcr-pull

replicaCount: 1

secrets:
  enabled: true
  keyvaultName: kv-mb-local
  managedIdentityClientId: ""
  tenantId: "11111111-1111-1111-1111-111111111111"
  objects:
    - name: $SECRET_NAME
      env: $ENV_VAR
  syncK8sSecretName: $NAME-secrets
YAML
  echo "created: $VALUES_FILE"
fi

# ── 2. env.hcl entry ─────────────────────────────────────────────────────────
SA="${NAME}-sa"
ENTRY="    $NAME = { namespace = \"$NAME\", service_account = \"$SA\", secret_name = \"$SECRET_NAME\" }"

if grep -qF "\"$NAME\"" "$ENV_HCL"; then
  echo "skip: $NAME already in env.hcl"
else
  # Insert the new entry before the closing brace of the services block.
  # Pattern: last line of the form "  }" that closes the services = { ... } block.
  # We use a sed approach: insert before the line that is exactly "  }".
  sed -i "0,/^  }$/!b; /^  }$/{s/^  }$/  }\n/; b}; /^  }$/i\\$ENTRY" "$ENV_HCL" 2>/dev/null || true

  # Fallback: Python-based insert (more reliable across sed versions).
  python3 - "$ENV_HCL" "$ENTRY" <<'PY'
import sys
path, entry = sys.argv[1], sys.argv[2]
lines = open(path).readlines()

# Normalize inline empty map: "services = {}" -> "services = {\n  }\n"
for i, line in enumerate(lines):
    stripped = line.strip()
    if 'services' in stripped and '=' in stripped and stripped.endswith('{}') and '{' not in stripped.replace('services', '').replace('=', '').replace('{}', ''):
        indent = line[: len(line) - len(line.lstrip())]
        lines[i] = line.rstrip()[:-1] + '\n'  # remove trailing }
        lines.insert(i + 1, indent + '}\n')
        break

# Find services block then its closing brace (skip lines that already have '{' and '}' on the same line).
in_services = False
insert_at = None
for i, line in enumerate(lines):
    stripped = line.strip()
    if not in_services and 'services' in stripped and '=' in stripped and stripped.count('{') > stripped.count('}'):
        in_services = True
        continue
    if in_services and stripped == '}':
        insert_at = i
        break

if insert_at is None:
    print("ERROR: could not find services block closing brace", file=sys.stderr)
    sys.exit(1)
if entry in ''.join(lines):
    sys.exit(0)
lines.insert(insert_at, entry + "\n")
open(path, 'w').writelines(lines)
PY
  echo "added:   $NAME in $ENV_HCL"
fi

# ── 3. terragrunt apply ───────────────────────────────────────────────────────
TF_LOCAL="$REPO_ROOT/infrastructure/live-k8s/local"
echo "running: terragrunt run-all apply ..."
(cd "$TF_LOCAL" && terragrunt run-all apply --terragrunt-non-interactive 2>&1)

# ── 4. inject clientId into values.yaml ──────────────────────────────────────
TENANT_ID="${ARM_TENANT_ID:-11111111-1111-1111-1111-111111111111}"
identities_json=$(cd "$TF_LOCAL/managed-identity" && terragrunt output -json service_identities 2>/dev/null)

python3 - "$identities_json" "$REPO_ROOT/gitops/local/values" "$TENANT_ID" <<'PY'
import sys, json, re, os
identities, values_root, tenant_id = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]
for svc, info in identities.items():
    f = os.path.join(values_root, svc, "values.yaml")
    if not os.path.exists(f): continue
    t = open(f).read()
    t = re.sub(r'(managedIdentityClientId:\s*)(".*?"|[^\s#\n]+)', f'managedIdentityClientId: "{info["client_id"]}"', t)
    t = re.sub(r'(tenantId:\s*)(".*?"|[^\s#\n]+)', f'tenantId: "{tenant_id}"', t)
    open(f, "w").write(t)
    print(f"patched: {svc}  clientId={info['client_id']}")
PY

echo ""
echo "done. Manually push to trigger ArgoCD:"
echo "  git add $VALUES_FILE $ENV_HCL && git commit -m 'add service $NAME' && git push"
