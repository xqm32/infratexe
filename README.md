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
Makefile                   bootstrap / status / reconcile / teardown helpers
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
./bootstrap/bootstrap.sh          # k3s + kubeconfig + Flux seed, idempotent
flux get kustomizations --watch   # watch git take over
make status
```

See [bootstrap/README.md](bootstrap/README.md) for the individual steps and why
`bootstrap.sh` overrides k3s's default pod/service CIDRs.

After step 3 everything else — namespaces, workloads, the Traefik wiring — is applied by Flux from git.
To change the cluster, open a PR against this repo; to force a reconcile, `flux reconcile kustomization flux-system --with-source`.

## Access

Expose port `8000` (Traefik's `web` entrypoint) as the VM's default proxy port, then:

```
https://curling-lathe.exe.xyz/           # the hello world app (private to VM users by default)
http://localhost:8000/                   # same thing, straight to Traefik from the VM
```

The VM's exe.dev proxy port is `8000`; Traefik binds it as a `hostPort` and routes by
Ingress. Both the edge proxy and ServiceLB (node :80/:443) hit the same Traefik, so
the app stays reachable if the proxy target ever changes.

Other ports in 3000-9999 are proxied as well, e.g. `https://curling-lathe.exe.xyz:8080/`.

## Verify

```bash
$ kubectl get nodes
NAME            STATUS   ROLES           AGE   VERSION
curling-lathe   Ready    control-plane   20m   v1.37.2+k3s1

$ flux get kustomizations
NAME             REVISION            READY   MESSAGE
apps             main@sha1:e8691a4e  True    Applied revision: main@sha1:e8691a4e
flux-system      main@sha1:e8691a4e  True    Applied revision: main@sha1:e8691a4e
infrastructure   main@sha1:e8691a4e  True    Applied revision: main@sha1:e8691a4e

$ curl -s localhost:8000/
Server address: 10.52.0.18:80
Server name: hello-5dc54b477d-mwzgg
```

The git -> cluster loop was verified by editing `replicas` in
`apps/hello/deployment.yaml`, pushing, and watching a third pod appear with no
`kubectl` involved.

From outside the VM the exe.dev proxy answers `307` to `https://curling-lathe.exe.xyz/`
until you log in with your exe.dev account (the proxy is private by default). To make
the hello world public: `ssh exe.dev share set-public curling-lathe`
(and `share set-private` to undo).

## Operating notes

- k3s and Flux both run as systemd units and restart with the VM; Flux re-syncs git on
  every controller start, so a reboot converges back to whatever `main` says.
- kubeconfig for humans lives at `~/.kube/config` (copied from `/etc/rancher/k3s/k3s.yaml`).
- `make status` / `make reconcile` / `make teardown` for the daily drivers.
- Nothing in git is a secret, and nothing needs to be: exe.dev injects service
  credentials at the network edge (`https://reflection.int.exe.xyz/integrations`).
