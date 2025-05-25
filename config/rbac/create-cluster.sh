#!/usr/bin/env bash
# Configurable name
NAMESPACE="rbac-test"
CLUSTER="cluster-for-rbac"
#value set later
API_URL=""

set -e

echo "Delete pre existing cluster"

kind delete cluster --name "$CLUSTER"

echo "Create cluster"
kind create cluster --config ./cluster-for-rbac.yaml

echo "Link kubectl to cluster"

kubectl cluster-info --context kind-cluster-for-rbac

echo "Run the script to create the Uthred user csr"
cd uthred
./script.sh
cd ..

echo "Applying the CSR to the cluster"
kubectl apply -f ./uthred/uthred-csr.yaml

echo "Approving Uthred CSR"
kubectl certificate approve uthred-csr

echo "Extracting user certificate uthred.crt for authentication"
#kubectl get csr/uthred-csr -o jsonpath="{.status.certificate}" | base64 -d > ./uthred/uthred.crt

TIMEOUT=60  # seconds
INTERVAL=2  # seconds
ELAPSED=0
while true; do
  CERT=$(kubectl get csr/uthred-csr -o jsonpath='{.status.certificate}')

  if [[ -n "$CERT" ]]; then
    echo "✅ Certificate is available for CSR: $CSR_NAME"
    echo "$CERT" | base64 -d > ./uthred/uthred.crt
    break
  fi

  if (( ELAPSED >= TIMEOUT )); then
    echo "❌ Timeout waiting for certificate issuance of CSR: $CSR_NAME"
    exit 1
  fi

  sleep "$INTERVAL"
  ((ELAPSED+=INTERVAL))
done


echo "Extracting ca.crt"
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt

echo "Extracting API url"
API_URL=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')
echo "API_URL=$API_URL"

echo "Create the ${NAMESPACE} namespace"
kubectl create namespace "$NAMESPACE"

echo "Change the kubectl context to link to the namespace"
kubectl config set-context --current --namespace="$NAMESPACE"

echo "Create example pods"
kubectl apply -f ../networking/backend-deployment.yaml

echo "Sending initial call with expected forbidden"
CURL_COMMAND="curl ${API_URL}/api/v1/namespaces/${NAMESPACE}/pods --cacert ./ca.crt --cert ./uthred/uthred.crt --key ./uthred/uthred.key"
echo "$CURL_COMMAND"
eval "$CURL_COMMAND"

echo "Creating role and role binding to give access to the user"
kubectl apply -f pod-reader-role.yaml
kubectl apply -f uthred-pod-reader-rolebinding.yaml

echo "The command should get the pods"
eval "$CURL_COMMAND"












