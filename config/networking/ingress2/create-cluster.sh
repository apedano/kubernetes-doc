#!/usr/bin/env bash

echo "From https://kk-shichao.medium.com/expose-service-using-nginx-ingress-in-kind-cluster-from-wsl2-14492e153e99"
echo "https://dustinspecker.com/posts/test-ingress-in-kind/"

echo "Delete pre existing cluster"


kind delete cluster --name cluster-for-ingress

echo "Create cluster"
kind create cluster --config ./cluster-for-ingress.yaml

echo "Link kubectl to cluster"

kubectl cluster-info --context cluster-for-ingress








