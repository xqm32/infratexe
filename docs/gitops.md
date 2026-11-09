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
