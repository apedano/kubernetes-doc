#!/usr/bin/env bash
echo "Delete pre existing cluster"

kind delete cluster --name cluster-for-headless

echo "Create cluster"
kind create cluster --config ./cluster-for-headless.yaml

echo "Link kubectl to cluster"

kubectl cluster-info --context cluster-for-headless

echo "Applying cluster"
kubectl apply -f ./workloads.yaml

echo "Only after pods are ready: kubectl exec -it my-headless-deployment-6c7f5cc86-986bn -- nslookup my-headless-service.default.svc.cluster.local"





