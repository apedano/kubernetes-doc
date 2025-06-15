#!/usr/bin/env bash

echo "Delete pre existing cluster"
./../delete-clusters.sh

echo "Create cluster-for-statefulset"
kind create cluster --config ./cluster-for-statefulset.yaml

echo "Link kubectl to cluster"
kubectl cluster-info --context cluster-for-statefulset

echo "Applying statefulset with headless service"
kubectl apply -f ./headless_service_statefulset.yaml





