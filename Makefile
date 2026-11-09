.DEFAULT_GOAL := status

.PHONY: bootstrap status reconcile sync teardown
bootstrap:  ## bare VM -> k3s + Flux (see bootstrap/README.md)
	./bootstrap/bootstrap.sh

status:  ## cluster + gitops state
	@kubectl get nodes
	@flux get sources git
	@flux get kustomizations
	@kubectl -n hello get deploy,svc,ing,pods

reconcile:  ## force a git pull + apply right now
	flux reconcile source git flux-system
	flux reconcile kustomization flux-system --with-source

sync:  ## apply local manifests to the cluster (emergency only; git is the source of truth)
	kubectl apply -k clusters/exe

teardown:  ## remove k3s and everything on it
	sudo /usr/local/bin/k3s-uninstall.sh
