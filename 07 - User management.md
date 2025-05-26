# 07 - User management

ubernetes **RBAC** (Role-Based Access Control) provides a powerful mechanism for
**controlling access to Kubernetes resources based on roles and permissions**.

## Unserstand `Role`, `RoleBinding`, `ClusterRole`, and `ClusterRoleBinding`

### `Role`

Define a set of permissions within a namespace.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: pod-manager
rules:
  - apiGroups: [ "" ]
    resources: [ "pods" ]
    verbs: [ "get", "list", "create", "delete" ]
```

### `RoleBinding`

The elements links a user `UseerAccount` to a specific `Role`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-manager-binding
  namespace: development
subjects:
  - kind: User
    name: developer
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-manager
  apiGroup: rbac.authorization.k8s.io
```

### `ClusterRole`

In this case the role is cluster-wide and not limited to a specific namespace

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-viewer
rules:
  - apiGroups: [ "" ]
    resources: [ "nodes" ]
    verbs: [ "get", "list" ]
```

### `ClusteRoleBinding`

Here we can link the role to a user of to a group

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-viewer-binding
subjects:
  - kind: Group
    name: ops-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-viewer
  apiGroup: rbac.authorization.k8s.io
```

## User accounts Vs ServiceAccount

| Feature                      | User Account                      | Service Account                                                                        |
|------------------------------|-----------------------------------|----------------------------------------------------------------------------------------|
| Purpose                      | Human users                       | Processes inside the cluster, inside a pod, for instance (git clone, list pods etc...) |
| Managed by                   | External system (e.g., IAM, OIDC) | Kubernetes itself                                                                      |
| Stored in Kubernetes         | ❌ No                              | ✅ Yes (`ServiceAccount` resource)                                                      |
| Automatic assignment to Pods | ❌ No                              | ✅ Yes                                                                                  |
| Authentication method        | Certificates, OIDC tokens, etc.   | ServiceAccount tokens (JWT)                                                            |
| Typical use                  | Admin, DevOps, CI/CD tools        | Applications, controllers                                                              |

## Create a user account in a Kubernetes cluster

To test RBAC we need to a user, so first create a new user.
Below is the step-by-step guide to creating a new user named Uthred in a Kubernetes cluster.

![csr_workflow.png](images%2F07%2Fcsr_workflow.png)

### Step1. Generate a private key (User)

```bash
openssl genrsa -out uthred.pem
```
[uthred.pem](config%2Frbac%2Futhred.pem)

### Step2. Generate a CertificateSigningRequest `csr` for the user (User)

```yaml
openssl req -new -key uthred.pem -out uthred.csr -subj "/CN=uthreed" 
```
The content is a `CERTIFICATE REQUEST`. We need to base64 it to add it to the CSR element

```bash
base64 -w 0 "uthred.csr" > "uthred.csr.b64"
```

The `-w 0` disables the line wrap, therefore the output is in one line only

The file has the following structure:

```bash
$ openssl req -in uthred.csr -inform PEM -noout -text

Certificate Request:
    Data:
        Version: 1 (0x0)
        Subject: CN = uthred
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (2048 bit)
                Modulus:
                    00:b8:7e:50:1b:3c:62:0c:eb:d6:ee:cd:ec:b2:83:
                    ...
                Exponent: 65537 (0x10001)
        Attributes:
            (none)
            Requested Extensions:
    Signature Algorithm: sha256WithRSAEncryption
    Signature Value:
        ac:31:bb:ba:f3:13:c8:a4:aa:ec:5c:1e:84:3b:11:ee:9c:d7:
        ...
```
The file contains the public key generated from the private one and the signature for the 
key verification.

And we can finally create the CSR element [uthred-csr.yaml](config%2Frbac%2Futhred-csr.yaml)

```yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: uthred-csr
spec:
  request: <base64 from uthred.csr.b64>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
```

### Step3. The user sends the CSR to the admin

### Step4. The admin creates the CSR in the cluster

```bash
$ kubectl create -f uthred.csr
certificatesigningrequest.certificates.k8s.io/uthred-csr created
```

### Step5. The admin approves or rejects the request

Theoretically, the admin can decide to grant or not access to the cluster to the requesting user.

So far the csr is in status `pending`

```bash
kubectl get csr
NAME         AGE   SIGNERNAME                                    REQUESTOR                                    REQUESTEDDURATION   CONDITION
uthred-csr   27m   kubernetes.io/kube-apiserver-client           kubernetes-admin                             24h                 Pending
```
The admin can approve with

```bash
$ kubectl certificate approve uthred-csr
certificatesigningrequest.certificates.k8s.io/uthred-csr approved
```
Now the status has changed.

### Step6. The admin provides the user with the signed certificate

The admin extracts the certificate from the approved csr, which is **signed with the cluster CA**.

```bash
$ kubectl get csr/uthred-csr -o jsonpath="{.status.certificate}" | base64 -d > uthred.crt
```
If we verify the certificate we will see

```bash
$ openssl x509 -in uthred.crt -noout -text

Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            2d:68:16:b8:5a:fb:74:6d:3f:85:c9:64:62:51:cb:1d
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN = kubernetes
        Validity
            Not Before: May 25 14:45:03 2025 GMT
            Not After : May 26 14:45:03 2025 GMT
        Subject: CN = uthred
```
And we see it is signed (Issuer) by kubernetes which is the CA (ca.crt) in the following step

#### `ca.crt` and api url

The admin can also extract the CA certificate and the API url to be used by the user

```bash
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
```

and

```bash
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}' 
https://127.0.0.1:34795
```

### Step7. The user can use the certificate to forward requests to the cluster

First we extract the CA certificate

```bash
$ curl https://127.0.0.1:34795/api/v1/namespaces/default/pods --cacert ca.crt --cert uthred.crt --key uthred.key 

{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "pods is forbidden: User \"uthred\" cannot list resource \"pods\" in API group \"\" in the namespace \"default\"",
  "reason": "Forbidden",
  "details": {
    "kind": "pods"
  },
  "code": 403
```

We see that the user cannot access the resource because it is not added to any role in the cluster.

## Add the user to a role

A simple role could be a `pod-reader`

[pod-reader-role.yaml](config%2Frbac%2Fpod-reader-role.yaml)

### Create the RoleBinding

[uthred-pod-reader-rolebinding.yaml](config%2Frbac%2Futhred-pod-reader-rolebinding.yaml)

```bash
$ kubectl apply -f pod-reader-role.yaml
role.rbac.authorization.k8s.io/pod-reader unchanged

$ kubectl apply -f uthred-pod-reader-rolebinding.yaml
rolebinding.rbac.authorization.k8s.io/uthred-pod-reader unchanged
```
The curl command is now executable.

# 🛡️ Kubernetes ServiceAccount Example

This example demonstrates how to create a `ServiceAccount`, a `Role`, and a `RoleBinding` in a specific namespace of a Kubernetes cluster (e.g., a `kind` cluster).

---

## 📄 Step-by-Step YAML Manifests

### 1. **Create a Namespace (Optional)**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rbac-test
```

---

### 2. **Create a ServiceAccount**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-list-serviceaccount
  namespace: rbac-test
```

---

### 3. **Create a Role with Limited Permissions**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: rbac-test
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
```

---

### 4. **Bind the Role to the ServiceAccount**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-binding
  namespace: rbac-test
subjects:
- kind: ServiceAccount
  name: pod-reader
  namespace: rbac-test
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```
The role binding in the previous example can be reused as in:

[uthred-pod-reader-rolebinding.yaml](config%2Frbac%2Futhred-pod-reader-rolebinding.yaml)

---

## ✅ Usage

Once applied, the ServiceAccount `pod-list-serviceaccount` in `rbac-test` can be used by Pods to list/watch/get pods in that namespace.

You can associate it with a Pod like this:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: serviceaccount-pod
  namespace: rbac-test
spec:
  serviceAccountName: pod-list-serviceaccount
  containers:
    - name: kubectl-container
      image: bitnami/kubectl:latest
      command: ["sleep", "3600"]
```

We can test the pod
```bash
$ kubectl apply -f serviceaccount-pod.yaml
pod/serviceaccount-pod created

$kubectl exec -it serviceaccount-pod -- sh

    $ kubectl get pods
    NAME                                  READY   STATUS    RESTARTS   AGE
    backend-deployment-76cfdcfdd8-8gxkh   1/1     Running   0          48m
    backend-deployment-76cfdcfdd8-gkzg8   1/1     Running   0          48m
    serviceaccount-pod                    1/1     Running   0          34s
```
















