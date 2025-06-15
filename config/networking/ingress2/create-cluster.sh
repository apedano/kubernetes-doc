#!/usr/bin/env bash
echo "Delete pre existing cluster"


kind delete cluster --name cluster-for-ingress

echo "Create cluster"
kind create cluster --config ./cluster-for-ingress.yaml

echo "Link kubectl to cluster"

kubectl cluster-info --context cluster-for-ingress








