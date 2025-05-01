#!/usr/bin/env bash

echo "Delete pre existing cluster"

kind delete cluster --name my-two-node-cluster

echo "Create my-two-nodes-cluster cluster"
kind create cluster --config ./kube-config/my-two-nodes-cluster-config.yaml

echo "Link kubectl to cluster"

kubectl cluster-info --context kind-my-two-node-cluster

echo "Label removal to allow load balancer traffic on control pane"
kubectl label node my-two-node-cluster-control-plane node.kubernetes.io/exclude-from-external-load-balancers-

echo "Adding backend and frontend deployements and services"
kubectl apply -f ./kube-config/networking/

echo "Setting the path for go installed packages"
export PATH="/root/go/bin/:$PATH"
cloud-provider-kind --enable-lb-port-mapping





