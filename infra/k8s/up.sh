#!/usr/bin/env bash
# Reproducible up/down for the Android build+test stack. Needs: kubectl context for a real cluster + a pushed image.
#   infra/k8s/up.sh [tcg|kvm]  → apply, wait for build + tests, print results
#   infra/k8s/down.sh       → delete namespace (PVC included)
set -euo pipefail
D=$(dirname "$0"); K=$D/overlays/${1:-tcg}
kubectl apply -k "$K"
kubectl -n glance-android wait --for=condition=complete job/glance-build --timeout=30m
kubectl -n glance-android wait --for=condition=complete job/glance-test --timeout=40m || true
kubectl -n glance-android logs job/glance-test --tail=40
