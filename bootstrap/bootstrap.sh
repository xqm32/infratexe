#!/usr/bin/env bash
# One-shot bootstrap: bare exe.dev VM -> k3s + Flux-managed cluster.
# Safe to read top-to-bottom; re-running on an already-bootstrapped VM is a no-op
# except for `kubectl apply` of the Flux seed manifests.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.int.exe.xyz/xqm32/infratexe.git}"
CLUSTER="${CLUSTER:-exe}"

# The exe.dev VM network is 10.42.0.0/16 (VM itself is 10.42.0.x, gateway 10.42.0.1).
# k3s defaults to exactly that range for pods, which shadows the VM's own subnet and
# breaks egress. Use disjoint ranges.
POD_CIDR="${POD_CIDR:-10.52.0.0/16}"
SVC_CIDR="${SVC_CIDR:-10.53.0.0/16}"
CLUSTER_DNS="${CLUSTER_DNS:-10.53.0.10}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "installing k3s (pods=$POD_CIDR services=$SVC_CIDR)"
if systemctl list-unit-files k3s.service >/dev/null 2>&1 && systemctl is-active --quiet k3s; then
  echo "k3s already running; skipping install"
else
  INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode=644 \
    --cluster-cidr=${POD_CIDR} \
    --service-cidr=${SVC_CIDR} \
    --cluster-dns=${CLUSTER_DNS}" \
  sh "$(dirname "$0")/install-k3s.sh"
fi

log "kubeconfig"
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
kubectl get nodes

log "waiting for k3s core components"
kubectl -n kube-system wait --for=condition=Available deploy/coredns --timeout=180s
kubectl -n kube-system wait --for=condition=Ready pod -l app.kubernetes.io/name=traefik --timeout=180s

log "seeding Flux (controllers + sync objects)"
kubectl apply -f "$(dirname "$0")/../clusters/${CLUSTER}/flux-system/gotk-components.yaml"
kubectl apply -f "$(dirname "$0")/../clusters/${CLUSTER}/flux-system/gotk-sync.yaml"

log "done. watch with: flux get kustomizations --watch"
echo "Repo: $REPO_URL"
