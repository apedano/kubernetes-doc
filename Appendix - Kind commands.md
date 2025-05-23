# Kind main commands

https://kind.sigs.k8s.io/docs/user/quick-start/

## Create a kind cluster based on config

The config is in the folder pointed by the symbolic link created before

```bash
kind create cluster --config ./kube-config/my-two-nodes-cluster-config.yaml
```

```bash
# cluster-config.yml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings: #Allows creation of NodePort service for external access
    - containerPort: 30000
      hostPort: 30000
      protocol: TCP
```

## Create a kind cluster based on script

The cluster can be created with the following script

[create-cluster.sh](config%2Fcreate-cluster.sh)

```bash
./kube-config/create-cluster.sh
```

Doing the following operations

### Deletion of pre existing cluster

Deletes the cluster from config file if exists

### Cluster creation from config file

Creates the cluster with the config file from the previous section,
including the `extraPortMappings` section for `NodePort`


### Link kubectl to the cluster

```bash
kubectl cluster-info --context kind-my-two-node-cluster
Kubernetes control plane is running at https://127.0.0.1:34409
CoreDNS is running at https://127.0.0.1:34409/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### Allowing load balancers access to control plane nodes
By default, Kubernetes expects workloads will not run on control plane nodes and labels them with

`node.kubernetes.io/exclude-from-external-load-balancers`

This label stops load balancers from accessing them.

If you are running workloads on control plane nodes, as is the default kind configuration, you will need to **remove this label** to access them using a LoadBalancer:

```shell

$ kubectl label node <control-pane-node-name> node.kubernetes.io/exclude-from-external-load-balancers-

node/my-two-node-cluster-control-plane unlabeled
```

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


## Connect a terminal to a cluster node

We can connect to any node with the following

```bash
podman ps
```

And identify the name of the cluster's master node: `my-two-node-cluster-control-plane`
Now we connect to it

```bash
podman exec -it my-two-node-cluster-control-plane bash
```

### Get the IP address

```bash
podman inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' <KIND_NODE_CONTAINER_NAME>
```




