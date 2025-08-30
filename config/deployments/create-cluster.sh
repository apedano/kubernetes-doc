#!/usr/bin/env bash

echo "Delete pre existing cluster"
./../delete-clusters.sh

echo "Create cluster-for-deployments"
kind create cluster --config ./cluster-for-deployments.yaml

echo "Link kubectl to cluster"
kubectl cluster-info --context cluster-for-deployments

echo "Applying deployment"

kubectl apply -f busybox-deployment.yaml





