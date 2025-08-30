#!/usr/bin/env bash

echo "Initial cleanup"
kubectl delete all -l app=backend

echo "Deploying version 1"
kubectl apply -f backend-deployment-v1.yaml

echo "Deploying v2"
kubectl apply -f backend-deployment-v2.yaml

echo "Deploy service"
kubectl apply -f backend-service.yaml

echo "Wating for deployments to be available"
kubectl wait deployment/backend-deployment-v1 --for=condition=available --timeout=60s
kubectl wait deployment/backend-deployment-v2 --for=condition=available --timeout=60s

# kubectl get pods shows V1 and v2 pods
#NAME                                     READY   STATUS    RESTARTS   AGE
#backend-deployment-v1-7c968bff9c-7lnlq   1/1     Running   0          7m39s
#backend-deployment-v1-7c968bff9c-b2hdq   1/1     Running   0          7m39s
#backend-deployment-v1-7c968bff9c-d7x46   1/1     Running   0          7m39s
#backend-deployment-v1-7c968bff9c-nvx6w   1/1     Running   0          7m39s
#backend-deployment-v2-6c8d48575d-nlb4m   1/1     Running   0          7m39s
kubectl get pods


kubectl run curl-client --rm -i --tty --image=curlimages/curl -- /bin/sh

# Then, when all pods are running, you can safely delete the old deployment
#$ kubectl delete deploy my-app-v1

#echo "Final cleanup"
#kubectl delete all -l app=backend