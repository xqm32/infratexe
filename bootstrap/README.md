# Bootstrap

One-time manual steps that turn a bare exe.dev VM into a Flux-managed cluster.
Everything after step 3 is owned by git.

## 0. Prereqs

- Ubuntu 24.04 VM (2 vCPU / 7 GB is plenty), `sudo` available
- Port 80/443/8000 free

## 1. k3s

`bootstrap/install-k3s.sh` is the upstream `get.k3s.io` installer, vendored so the
cluster can be rebuilt even if upstream moves. k3s default components are kept:
CoreDNS, Traefik (ingress), ServiceLB (klipper, binds node :80/:443), local-path
storage, metrics-server.

```bash
sudo INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644" sh bootstrap/install-k3s.sh
mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown $USER ~/.kube/config
kubectl get nodes
```

> Note: on a brand-new k3s the `helm-install-traefik` job can fail once because the
> Traefik CRD chart has not registered its CRDs yet. It retries and succeeds; no action needed.

## 2. Flux CLI (only needed for `flux get/logs/reconcile` conveniences)

```bash
curl -s https://fluxcd.io/install.sh | sudo bash
flux --version
```

## 3. Seed Flux ("bootstrap")

Flux bootstrapping normally means `flux bootstrap git`, which needs push credentials.
The manifests here are the output of that command, committed by hand, so the seed is:

```bash
kubectl apply -f clusters/exe/flux-system/gotk-components.yaml   # controllers + CRDs
kubectl apply -f clusters/exe/flux-system/gotk-sync.yaml          # GitRepository + root Kustomization
```

From that point the cluster pulls this repo and reconciles itself. Flux also manages
its own manifests: `flux-system/kustomization.yaml` includes `gotk-components.yaml`,
so upgrading Flux is a git commit too.

Auth: the repo is readable over HTTPS without credentials from this VM (the exe.dev
GitHub integration injects access at the network edge), so the `GitRepository` uses
an anonymous `https://` URL. Swap in a `secretRef` with a deploy key if you move to a
repo that needs auth.
