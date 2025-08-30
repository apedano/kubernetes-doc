#!/usr/bin/env bash

echo "Initial cleanup"
kubectl delete all -l app=busybox

echo "Deploying version 1.36"
kubectl apply -f busybox-deployment-1.36.yaml

echo "Deploy service"
kubectl apply -f busybox-service.yaml

echo "Wating for deployment to be available"
kubectl wait deployment/busybox-deployment-v1-36 --for=condition=available --timeout=60s

echo "Read logs containing 1.36"
kubectl logs service/busybox

echo "Deploying v1.37"
kubectl apply -f busybox-deployment-1.37.yaml

echo "Wating for deployment to be available"
kubectl rollout status deploy busybox-deployment-v1-37 -w

echo "Switching the service to v1.37"
kubectl patch service busybox -p '{"spec":{"selector":{"version":"1.37"}}}'

echo "Read logs containing 1.37"
kubectl logs service/busybox

echo "Deleting v1.36 deployment"
kubectl delete deployment/busybox-deployment-v1-36

echo "Final cleanup"
kubectl delete all -l app=busybox