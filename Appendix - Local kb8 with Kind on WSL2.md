# Appendix - Local kb8 with Kind on WSL2

[kind](https://kind.sigs.k8s.io/ ) is a tool for running local Kubernetes clusters using Docker container “nodes”.
kind was primarily designed for testing Kubernetes itself, but may be used for local development or CI.


## Install ubuntu on WSL2 (Windows)

https://documentation.ubuntu.com/wsl/en/latest/howto/install-ubuntu-wsl2/

### Reset user password

* Close all WSL instances.

* Open PowerShell as administrator.

* Run the following command, replacing `<distro_name>` with your Ubuntu distribution name (e.g., Ubuntu):

```PowerShell
ubuntu config --default-user root
```
This command changes the default user to `root`.

* Open your Ubuntu distribution.

Run the following command to change the password for your user, replacing `<your_username>` with your actual username:

```bash
passwd <your_username>
Enter the new password when prompted.
```
* Close the Ubuntu terminal.

In powershell, change the default user back to your username.

```PowerShell
ubuntu config --default-user <your_username>
```
pedaa00 123456

### Access Ubuntu file system externally

For WSL 2:
The easiest way to access your WSL 2 files is through the network path: `\\wsl$`
Open File Explorer and type `\\wsl$` in the address bar.
This will display your installed WSL distributions.
From there, you can navigate to your Ubuntu home folder (e.g., `\\wsl$\Ubuntu\home\<your_username>`).

#### Create a symbolic link to a folder in Windows

```bash
ln -s /mnt/c/projects/kubernetes-doc/config ./kube-config
```

#### WSL2 commands

| Command                  | Description                  |
|--------------------------|------------------------------|
| `wsl --terminate <distro>` |                              |
| `wsl --list --verbose` |                              |
| `wsl --set-version <distro> 2` | Convert WSL1 distros in WSL2 |

## Kind installation


### Install go

```bash
snap install go --classic
```

### Install podman

Instead of using Docker as image runtime, we use podman 

```bash
# Ubuntu 20.10 and newer
sudo apt-get update
sudo apt-get -y install podman
```

### Install kind from binaries

```bash
# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-arm64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### Install kubectl

```bash
snap install kubectl --classic
```

### Create a kind cluster based on config

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

### Create a kind cluster based on script

The cluster can be created with the following script

[create-cluster.sh](config%2Fcreate-cluster.sh)

```bash
./kube-config/create-cluster.sh
```

Doing the following operations

#### Deletion of pre existing cluster

Deletes the cluster from config file if exists

#### Cluster creation from config file

Creates the cluster with the config file from the previous section, 
including the `extraPortMappings` section for `NodePort`


#### Link kubectl to the cluster

```bash
kubectl cluster-info --context kind-my-two-node-cluster
Kubernetes control plane is running at https://127.0.0.1:34409
CoreDNS is running at https://127.0.0.1:34409/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

#### Allowing load balancers access to control plane nodes
By default, Kubernetes expects workloads will not run on control plane nodes and labels them with

`node.kubernetes.io/exclude-from-external-load-balancers`

This label stops load balancers from accessing them.

If you are running workloads on control plane nodes, as is the default kind configuration, you will need to **remove this label** to access them using a LoadBalancer:

```shell

$ kubectl label node <control-pane-node-name> node.kubernetes.io/exclude-from-external-load-balancers-

node/my-two-node-cluster-control-plane unlabeled
```

## Expose workloads outside the cluster


### Method1: Test NodePort service for external access

This method uses the cluster port mapping defined in the cluster config file

Create deployment
```bash
kubectl create deployment nginx --image=nginx --port=80
```
create service of type `NodePort` pointing to the port mapping of the cluster
```bash
kubectl create service nodeport nginx --tcp=80:80 --node-port=30000
```

access service
```bash
 curl localhost:30000
```

### Method2: Setting up Load Balanacer - KIND 

Cloud Provider KIND can be installed using golang

```bash
go install sigs.k8s.io/cloud-provider-kind@latest
```

Then, on a separate Ubuntu console we can start the load balancer service with

```bash
cloud-provider-kind --enable-lb-port-mapping
```

> When using **podman**, it is very likely that you will need
> to add the flag `--enable-lb-port-mapping` to the cloud-provider-kind command. 
> This is due to podman not being able to bind to privileged ports by default.

### Testing the Load Balancer

To test the load balancer we can apply the following file to the cluster

[load-balancer-test-app-config.yaml](config%2Fload-balancer-test-app-config.yaml)

```bash
kubectl apply -f ./kube-config/load-balancer-test-app-config.yaml

pod/foo-app created
pod/bar-app created
service/foo-service created
```

Then we can test the load balancer with the following script

```bash
#LB_IP will contain the External IP exposed by the LB
LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo $LB_IP #10.89.1.10 in our cluster

# should output foo and bar depending on the lb assigned pod 
for i in {1..10}; do
  curl ${LB_IP}:5678
done
```
To delete the test content

```bash
kubectl delete -f ./kube-config/load-balancer-test-app-config.yaml

pod "foo-app" deleted
pod "bar-app" deleted
service "foo-service" deleted
```





