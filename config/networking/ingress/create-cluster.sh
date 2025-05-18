#!/usr/bin/env bash

echo "Delete pre existing cluster"

kind delete cluster --name cluster-for-ingress

echo "Create my-two-nodes-cluster cluster"
kind create cluster --config ./kube-config/networking/ingress/cluster-for-ingress.yaml

echo "Link kubectl to cluster"

kubectl cluster-info --context cluster-for-ingress

echo "Installing Nginx ingress controller"

kubectl apply -f ./kube-config/networking/ingress/deploy-ingress-nginx.yaml

echo "Waiting for status ready of the controller ..."

kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

echo "Nginx controller ready"

echo "Deploy sample app (hello-world) "



kubectl apply -f ./kube-config/networking/ingress/usage.yaml

echo "Setting the path for go installed packages"
#export PATH="/root/go/bin/:$PATH"


https://kind.sigs.k8s.io/docs/user/ingress



