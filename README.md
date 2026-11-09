# infratexe

A minimal, single-node, GitOps-managed Kubernetes cluster on an [exe.dev](https://exe.dev) VM.

- **Kubernetes**: [k3s](https://k3s.io) (single node, embedded etcd-free sqlite, Traefik + ServiceLB + local-path storage)
- **GitOps**: [Flux](https://fluxcd.io) v2 (`flux-system` reconciling this repo, `main` branch, every 1 minute on demand)
- **Hello world**: nginx demo served on `https://curling-lathe.exe.xyz/` through Traefik

```
exe.dev HTTPS proxy  ──►  VM :8000 (Traefik hostPort)  ──►  Ingress  ──►  hello Deployment (2 replicas)
                              ▲
                              │ HelmChartConfig (ports.web.hostPort)
Flux kustomize-controller ────┘  continually reconciles clusters/exe from git
```

## Repo layout

```
bootstrap/                 how a bare VM becomes this cluster (run once, by hand)
clusters/exe/              Flux sync root for the "exe" cluster (GitRepository + Kustomizations)
  flux-system/             Flux controllers + sync manifests
  infrastructure.yaml      Flux Kustomization -> ./infrastructure
  apps.yaml                Flux Kustomization -> ./apps
infrastructure/
  traefik/                 Traefik HelmChartConfig (expose web entrypoint on VM hostPort 8000)
apps/
  hello/                   the hello world workload (Namespace, Deployment, Service, Ingress)
docs/gitops.md             notes on how reconciliation works
```

## Bootstrap a fresh VM

```bash
# 1. install k3s (Traefik + ServiceLB + local-path come with it)
sudo INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644" sh bootstrap/install-k3s.sh

# 2. put the kubeconfig somewhere kubectl finds it
mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown $USER ~/.kube/config

# 3. install the Flux controllers + sync objects (one-time seed; Flux owns itself afterwards)
kubectl apply -f clusters/exe/flux-system/gotk-components.yaml
kubectl apply -f clusters/exe/flux-system/gotk-sync.yaml

# 4. watch it converge
flux get kustomizations --watch
kubectl -n hello get pods
```

After step 3 everything else — namespaces, workloads, the Traefik wiring — is applied by Flux from git.
To change the cluster, open a PR against this repo; to force a reconcile, `flux reconcile kustomization flux-system --with-source`.

## Access

Expose port `8000` (Traefik's `web` entrypoint) as the VM's default proxy port, then:

```
https://curling-lathe.exe.xyz/           # the hello world app (private to VM users by default)
```

Other ports in 3000-9999 are proxied as well, e.g. `https://curling-lathe.exe.xyz:8080/`.
