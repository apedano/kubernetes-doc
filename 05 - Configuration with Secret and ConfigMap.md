# 05 - Configuration with Secret and ConfigMap

## Configuring workload overriging `ENTRYPOINT` and `CMD`

> The two Docker directives `ENTRYPOINT` (the **command**) and `CMD` (the **arguments**) are used as startup commands
> for the base images running in a container

Example

```dockerfile
# Dockerfile
FROM node:12

ENTRYPOINT ["node", "app.js"]
CMD ["--listen-port", "8080"]
```

![entry_cmd.png](images%2F05%2Fentry_cmd.png)

We can override those by adding the `command` and `args` directive to the container section of a pod

```yaml
kind: Pod
spec:
  containers:
    - name: example
      image: luksa/kiada:latest
      command: [ "node", "test.js" ]
      arguments: [ "--listen-port", "9090" ]
```

So that the main command from `node app.js --listen-port 8080` becomes `node app.js --listen-port 8080`

## `ConfigMap` and `Secret` fiedls

| Secret       | ConfigMap    | Description                                                                                                            |
|--------------|--------------|------------------------------------------------------------------------------------------------------------------------|
| `data`       | `binaryData` | A map of key-value pairs. The values are Base64-encoded strings.                                                       |
| `stringData` | `data`       | A map of key-value pairs. The values are plain text strings. The `stringData` field in secrets is write-only.          |
| `immutable`  | `immutable`  | A boolean value indicating whether the data stored in the object can be updated or not.                                |
| `type`       | N/A          | A string indicating the type of secret. Can be any string value, but several built-in types have special requirements. |

### `Secret` specific field type

#### `Opaque` 

The default value

#### `bootstrap.kubernetes.io/token`

* Allow kubelets to join the cluster.

* Authenticate kubelets to the control plane to request TLS client certificates.

* Support temporary credentials during cluster joining

````yaml
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-abcdef
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  description: "bootstrap token for kubelet join"
  #first part of the token
  token-id: abcdef
  #second part of the token
  token-secret: 0123456789abcdef
  expiration: 2025-06-01T00:00:00Z
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
````

It is used 

1. You create a bootstrap token in the kube-system namespace.

The kubelet on a new node uses this token in its bootstrap-kubeconfig to connect to the API server.

1. If valid, the API server authenticates the kubelet using this token.

1. The kubelet sends a **CertificateSigningRequest** (CSR).

1. The cluster's controller-manager (via CSR approval) may auto-approve the request (if RBAC and config allow it).

1. Once approved, the kubelet gets a signed TLS client certificate and uses it for normal API communication.

```yaml
kubeadm join <master_node_ip>:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:<hash>
```

#### `kubernetes.io/basic-auth`

It contains username and password to be used for basic authentication to an external service. 
The `Opaque` type can also be used

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth-secret
type: kubernetes.io/basic-auth
data:
  username: bXl1c2Vy        # base64 for 'myuser'
  password: bXlwYXNzd29yZA== # base64 for 'mypassword'
```

#### `kubernetes.io/dockercfg`

It contains data to coonect to an external Docker registry
Deprecated in favor of `dockerconfigjson`

#### `kubernetes.io/dockerconfigjson`

It’s a secret that stores a `.docker/config.json` file, which has the following format

```json
{
  "auths": {
    "https://index.docker.io/v1/": {
      "username": "myuser",
      "password": "mypassword",
      "email": "myuser@example.com",
      "auth": "bXl1c2VyOm15cGFzc3dvcmQ="  // base64(user:password)
    }
  }
}
```

The corresponding secret can be created with 

```bash
ubectl create secret docker-registry my-registry-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=myuser \
  --docker-password=mypassword \
  --docker-email=myuser@example.com
```

Otherwise the secret can be created with the JSON file content

The secret will look like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-registry-secret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-json>
```

The secret can be used in a POD config

```yaml
piVersion: v1
kind: Pod
metadata:
  name: private-pod
spec:
  containers:
    - name: myapp
      image: myregistry.io/myapp:latest
  imagePullSecrets:
    #The secret name
    - name: my-registry-secret
```

or is a ServiceAccount to be used in a POD

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-serviceaccount
imagePullSecrets:
  - name: my-registry-secret
```

and in the pod

```yaml
spec:
  serviceAccountName: my-serviceaccount
```

#### `kubernetes.io/service-account-token`

It identifies a Kubernetes service account

It’s a Secret object of a special type that contains:

A **token** (`token key`): a JWT signed by the cluster’s API server.

The **CA certificate** (`ca.crt)`: used to validate the server certificate of the API server.

The **namespace** (`namespace`): the namespace of the service account.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-service-account-token
  annotations:
    kubernetes.io/service-account.name: my-service-account
type: kubernetes.io/service-account-token
data:
  token: <base64-token>
  ca.crt: <base64-encoded-ca>
  namespace: <base64-namespace>
```
More info in the ServiceAccount dedicated section

#### `kubernetes.io/ssh-auth` 

This type of secret stores the private key used for SSH authentication. 
The private key must be stored under the key `ssh-privatekey` in the secret.

```yaml
kubectl create secret generic my-ssh-secret \
  --type=kubernetes.io/ssh-auth \
  --from-file=ssh-privatekey=/path/to/id_rsa
```

The resulting secret would be

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-ssh-secret
type: kubernetes.io/ssh-auth
#if data is used then the value must be base64 encoded
stringData:
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAA...
    -----END OPENSSH PRIVATE KEY-----
```

That can be used in a POD

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: git-clone
spec:
  containers:
  - name: git
    image: alpine/git
    command: ["sh", "-c", "git clone git@github.com:my-org/private-repo.git"]
    volumeMounts:
    - name: ssh
      mountPath: /root/.ssh
      readOnly: true
  volumes:
  - name: ssh
    secret:
      secretName: my-ssh-secret
      items:
      - key: ssh-privatekey
        path: id_rsa
```

### `kubernetes.io/tls`

he Kubernetes secret type **kubernetes.io/tls** is used to store TLS certificates and private keys, typically for:

* Securing Ingress (HTTPS) traffic.
* TLS between services or with external clients.
* Mounting into pods for custom TLS-based apps.

This type of secrets stores a TLS certificate and the associated private key. 
They must be stored in the secret under the key `tls.crt` and `tls.key`, respectively.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-tls-secret
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
```

Use in Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
spec:
  tls:
  - hosts:
    - example.com
    secretName: my-tls-secret
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

## Setting ENVIRONMENT varibles and placeholders

> We can set container environment variables, using placeholders to other variables only defined locally

```yaml
kind: Pod
metadata:
  name: kiada
spec:
  containers:
    - name: kiada
      image: luksa/kiada:0.4
      env:
        - name: POD_NAME
          value: kiada
        - name: INITIAL_STATUS_MESSAGE
          #Since NODE_VERSION is defined in the NodeJS image’s Dockerfile 
          #and not in the pod manifest, it can’t be resolved.
          value: My name is $(POD_NAME). I run NodeJS version $(NODE_VERSION).
```

Env vars defined by the image can be accessible using a shell command that will be executed inside the container and
thus
having access to all vars.

```yaml
containers:
  - name: main
    image: alpine
    command:
      - sh
      - -c
      - 'echo "Hostname is $HOSTNAME."; sleep infinity'
```

## Injecting `ConfigMap` in a pod

### Injecting into container env vars

A ConfigMap can be injected for single entries of for all of them

Single entry:

```yaml
kind: Pod
...
spec:
  containers:
    - name: kiada
      env:
        - name: INITIAL_STATUS_MESSAGE
          valueFrom:
            configMapKeyRef:
              name: kiada-config
              key: status-message
              optional: true
      volumeMounts:
        - ...
```

In the previous listing, the reference to the config map key is marked as `optional` so that the container can be
executed even if the config map or key is missing.

All config map

```yaml
kind: Pod
...
spec:
  containers:
    - name: kiada
      envFrom:
        - configMapRef:
            name: kiada-config
            optional: true
```

With this, the cm keys will be the var name with the corresponding value

We can apply with

```shell
kubectl apply -f ./kube-config/secret-configmap/
```

And then

```shell
kubectl exec -it pod/pod-with-env-from-config-map -- env
...
env-var=This is the env var value
status-message=This is the status message value
...

kubectl exec -it pod/pod-with-single-value-from-config-map -- env
...
VARIABLE_FROM_CONFIG_MAP=This is the env var value
...

kubectl exec -it pod/pod-with-env -- env
...
INITIAL_STATUS_MESSAGE=My name is kiada. I run NodeJS version $(NODE_VERSION).
...
```

### Injecting a ConfigMap as volume

[config-map-as-volume-cm.yaml](config%2Fsecret-configmap%2Fconfig-map-as-volume-cm.yaml)
[pod-with-config-map-as-volume.yaml](config%2Fsecret-configmap%2Fpod-with-config-map-as-volume.yaml)
The ConfigMap can contain literals or `binaryData` (created when a `--from-file` option is used with a binary file)
fields
In any case the configMap is mounted to the container file system and every entry key is a file name and the value is
the file content.

```yaml
spec:
  containers:
    - name: busybox
      image: busybox
      command: [ "sleep", "3600" ]
      volumeMounts:
        - name: files
          mountPath: /data/
  volumes:
    - name: files
      configMap:
        name: config-map-as-volume
```

```shell
root@LAPTOP-6ONT27E9:/home/pedaa00# kubectl exec -it pod/pod-with-config-map-as-volume -- sh
/ # cd data/
/data # ls
data.bin       library.bin    text-file.txt
/data # cat text-file.txt
string file content
```

Chapter 9 config map and secrets

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Configuring_applications_using_ConfigMaps_Secrets_and_the_Downward_API.html