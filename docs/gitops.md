# How this GitOps setup works

## Reconciliation chain

```
GitRepository flux-system (poll every 1m)
└── Kustomization flux-system        path ./clusters/exe   prune, wait
    ├── Kustomization infrastructure path ./infrastructure
    │   └── HelmChartConfig kube-system/traefik  (web entrypoint -> hostPort 8000)
    └── Kustomization apps           path ./apps  (dependsOn infrastructure)
        └── Namespace hello, Deployment, Service, Ingress
```

- `clusters/exe/flux-system/gotk-sync.yaml` is the only object applied by hand. It
  points Flux at `clusters/exe`.
- `clusters/exe/kustomization.yaml` lists the two Flux `Kustomization` objects
  (`infrastructure.yaml`, `apps.yaml`) so per-layer reconciliation, ordering
  (`dependsOn`), pruning and health checks are visible in `flux get kustomizations`.
- Anything committed under those paths is applied; anything removed is pruned.

## Why hostPort 8000 for Traefik

exe.dev terminates TLS at its edge proxy and forwards to the VM. The VM's default
proxy port is `8000` (any port 3000-9999 also works via `https://<vm>.exe.xyz:<port>/`).
k3s's Traefik normally listens on node ports 80/443 via ServiceLB (Klipper), which the
edge proxy does not forward, so `infrastructure/traefik` sets:

```yaml
ports:
  web:
    hostPort: 8000
```

Traefik keeps handling all Ingress routing inside the cluster; exe.dev just needs one
TCP port on the VM.

## Conventions

- One directory per cluster under `clusters/`, one per concern under `infrastructure/`,
  one per application under `apps/`.
- No Secrets in git. Use SOPS/age + `sops-secrets-operator` or sealed-secrets when
  something actually needs a credential (the exe.dev edge injects most service
  credentials, so nothing needs one today).
- Keep images pinned by digest if you want reproducible rollouts.

## Bootstrapping vs. reconciling

| Step | Who does it | How often |
| --- | --- | --- |
| install k3s, write kubeconfig | human (`bootstrap/bootstrap.sh`) | once per VM |
| apply `gotk-components.yaml` + `gotk-sync.yaml` | human, then Flux | once, then Flux keeps them reconciled |
| Traefik `hostPort`, namespaces, workloads | Flux (`kustomize-controller`) | every 1m git poll / 10m Kustomization interval |
| Flux upgrades | git commit of `clusters/exe/flux-system/gotk-components.yaml` (`flux install --export`) | as needed |

Kubernetes objects are applied with server-side apply. Anything committed under
`clusters/exe`, `infrastructure/`, `apps/` that disappears from git is pruned; the
`apps` Kustomization additionally `dependsOn` `infrastructure` and `wait: true`, so a
broken deployment shows up as a not-ready Kustomization instead of silently rolling on.

### Health checks and stuck reconciles

`wait: true` means a Kustomization waits for workloads to become ready (default 10m).
If you push a manifest that will never become ready, the reconcile stays `Unknown`
and blocks dependents until the timeout. Fix forward (revert in git), or clear it:

```bash
flux reconcile kustomization apps --with-source   # retry now
flux suspend kustomization apps                   # stop trying, then resume
```
