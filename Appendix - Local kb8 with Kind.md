# Appendix - Local kb8 with Kind

[kind](https://kind.sigs.k8s.io/ ) is a tool for running local Kubernetes clusters using Docker container “nodes”.
kind was primarily designed for testing Kubernetes itself, but may be used for local development or CI.

## Prerequisites on Windows

### GO installation 

Version 1.16+. Install from https://go.dev/dl/

When installed, it can be executed from Powershell.

### Podman installation

Install podman desktop to run Podman engin in the local OS.

Let the guided installation create a new Podman machine

Run `podman help` in the terminal for a list of commands to interact with Podman. 
For example, try the 'Create' button within the Containers tab of Podman Desktop and view your containers with podman:
```powershell
$ podman ps
```

If you have go 1.16+ and docker, podman or nerdctl installed
 
```powershell
 ; kind create cluster
```

### Kind initialization

```shell
go install sigs.k8s.io/kind@v0.27.0

go: downloading sigs.k8s.io/kind v0.27.0
go: downloading github.com/spf13/cobra v1.8.0
go: downloading al.essio.dev/pkg/shellescape v1.5.1
go: downloading github.com/pkg/errors v0.9.1
go: downloading github.com/spf13/pflag v1.0.5
go: downloading github.com/mattn/go-isatty v0.0.20
go: downloading github.com/pelletier/go-toml v1.9.5
go: downloading gopkg.in/yaml.v3 v3.0.1
go: downloading github.com/inconshreveable/mousetrap v1.1.0
go: downloading github.com/BurntSushi/toml v1.4.0
go: downloading github.com/evanphx/json-patch/v5 v5.6.0
go: downloading sigs.k8s.io/yaml v1.4.0
go: downloading github.com/google/safetext v0.0.0-20220905092116-b49f7bc46da2
```

## Cluster creation

```shell
kind create cluster

Creating cluster "kind" ...
 • Ensuring node image (kindest/node:v1.32.2) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.32.2) 🖼
 • Preparing nodes 📦   ...
 ✓ Preparing nodes 📦
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind
```

This will create a cluster named **kind**

To check if the cluster is running

```shell
kubectl cluster-info --context kind-kind

Kubernetes control plane is running at https://127.0.0.1:60922
CoreDNS is running at https://127.0.0.1:60922/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

`kubectl` will be also installed and configured to run with the local cluster

### Create a two nodes cluster

Use the following Powershell script

Start the two nodes cluster

[app_create_two_nodes_cluster.ps1](scripts%2Fapp_create_two_nodes_cluster.ps1)

This is the script output

```shell
Creating cluster "my-two-node-cluster" ...
 • Ensuring node image (kindest/node:v1.32.2) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.32.2) 🖼
 • Preparing nodes 📦 📦   ...
 ✓ Preparing nodes 📦 📦
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-my-two-node-cluster"
You can now use your cluster with:

kubectl cluster-info --context kind-my-two-node-cluster
# Set Kind context (if needed)
# If you have multiple Kind clusters, ensure you're targeting the right one.
# If you only have one, this might not be necessary.
# kind context <your_kind_cluster_name>

# Verify the cluster is running and has two control plane nodes
kubectl get nodes

# You should see output similar to:
#NAME                                STATUS   ROLES           AGE    VERSION
#my-two-node-cluster-control-plane   Ready    control-plane   105s   v1.32.2
#my-two-node-cluster-worker          Ready    <none>          91s    v1.32.2


# Access the cluster (kubectl is already configured by Kind)
kubectl cluster-info
```

### Kind main commands

https://kind.sigs.k8s.io/docs/user/quick-start/

| Command                                              | Description                             |
|------------------------------------------------------|-----------------------------------------|
| `kind create cluster --config <cluster_config_file>` | Creates a cluster with the given config |
| `kind get clusters`                                  | Get running clusters                    |
| `kind delete cluster --name <cluster_name>`          | Delete cluster with name                |

> Make sure that Podman is running and the containers linked to the cluster are running


| Podmain container name        | Description                            |
|-------------------------------|----------------------------------------|
| `kindccm-xxxxxx`              | The `kind` main container              |
| `<cluster_name>-control-pane` | The `cluster control pane container    |
| `<cluster_name>-worker`       | The n-th cluster worker node container |


### Expose network traffic 

https://kind.sigs.k8s.io/docs/user/loadbalancer/

Kind is very lightweight, so it doesn't include LoadBalancer or Ingress by default. 
We can install a simple load balancer exposing kind cluster services

**Cloud Provider KIND** runs as a standalone binary in your host and connects to your KIND cluster and provisions new Load Balancer containers for your Services. 
It requires privileges to open ports on the system and to connect to the container runtime.

Installation can be done with golang

```shell
go install sigs.k8s.io/cloud-provider-kind@latest
```

This will install the binary in `$GOBIN` (typically `~/go/bin`). 
Add this directory to your `PATH` environment variable.

#### Execute the load balancer

> Run the following in a Powershell window with admin rights

```shell
cloud-provider-kind
```

### Allowing load balancers access to control plane nodes
By default, Kubernetes expects workloads will not run on control plane nodes and labels them with 

`node.kubernetes.io/exclude-from-external-load-balancers`

This label stops load balancers from accessing them.

If you are running workloads on control plane nodes, as is the default kind configuration, you will need to remove this label to access them using a LoadBalancer:

```shell

$ kubectl label node <control-pane-node-name> node.kubernetes.io/exclude-from-external-load-balancers-

node/my-two-node-cluster-control-plane unlabeled
```


### Install a simple application to the kind cluster

Having the following configuration:
[foo-app-config.yaml](config%2Ffoo-app-config.yaml)

This application has two pods exposed by the LoadBalancer service.

we can deploy those to the cluster

```shell
kubectl apply -f config/load-balancer-test-app-config.yaml
pod/foo-app created
pod/bar-app created
service/foo-service created
```

Getting the service we can see that the EXTERNAL-IP is filled with the IP we can use to do external calls

```shell
kubectl get svc
NAME          TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
foo-service   LoadBalancer   10.96.181.252   10.89.0.10    5678:31934/TCP   13s
kubernetes    ClusterIP      10.96.0.1       <none>        443/TCP          5h54m
```

We can use the service target port to test the load balanced service

```shell
curl 10.89.0.10:5678
bar-app
```

