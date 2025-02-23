# 02 - Kubernetes main components

<!-- TOC -->
* [02 - Kubernetes main components](#02---kubernetes-main-components)
  * [Workloads](#workloads)
    * [POD](#pod)
    * [Deployment](#deployment)
    * [Service](#service)
    * [Job](#job)
    * [DaemonSets and StatefulSets](#daemonsets-and-statefulsets)
  * [Control plane components](#control-plane-components)
    * [API Server `kube-apiserver`](#api-server-kube-apiserver)
    * [Controller Manager (`kube-controller-manager`)](#controller-manager-kube-controller-manager)
      * [Controller types](#controller-types)
    * [Scheduler (`kube-scheduler`)](#scheduler-kube-scheduler)
    * [Etcd](#etcd)
    * [Cloud Controller Manager](#cloud-controller-manager)
  * [Node components](#node-components)
    * [Kubelet](#kubelet)
    * [Kube-Proxy](#kube-proxy)
    * [Container runtime - Container Runtime Interface](#container-runtime---container-runtime-interface)
  * [Kubernetes extensibility](#kubernetes-extensibility)
    * [Networking - Container Network Interface](#networking---container-network-interface)
    * [Storage](#storage)
    * [Container registry](#container-registry)
  * [Custom functionality - Custom Resource Definitions](#custom-functionality---custom-resource-definitions)
  * [Kubernetes and security](#kubernetes-and-security)
    * [Etcd encryption](#etcd-encryption)
    * [Securing API server](#securing-api-server)
<!-- TOC -->

Reference: https://spacelift.io/blog/kubernetes-architecture

Dropbox document: https://www.dropbox.com/home/Studio%20dbi/Kubernetes?preview=Kubernetes+architecture.docx

https://devopscube.com/kubernetes-architecture-explained/

## Workloads

### POD

![img.png](images/02/pod.png)

**Pods** are the fundamental compute unit in Kubernetes. 
A Pod is a **group of one or more containers that share the same specification, sharing the same environment** (storage, network infra etc...)

The containers in a Pod share **an IP Address and port space**, are always co-located and co-scheduled,
and run in a shared context on the same Node.

### Deployment

A Deployment wraps the lower-level ReplicaSet object. 
It guarantees a certain number of replicas of a Pod will be running in your cluster. 
Deployments also provide declarative updates for Pods; you describe the desired state, and the Deployment will automatically add, replace, and remove Pods to achieve it.

### Service

Services expose Pods as a network service. You use services to permit access to Pods, either within your cluster via automatic service discovery, or externally through an Ingress. (Read more: What is a Kubernetes Service?)
For more details look into the Kubernetes networking section

### Job

A Job starts one or more Pods and waits for them to successfully terminate. 
Kubernetes also provides CronJobs to automatically create Jobs on a recurring schedule.

### DaemonSets and StatefulSets

DaemonSets replicate a Pod to every Node in your cluster, while StatefulSets provide persistent replica identities.

See [StatefulSet vs. Deployment](https://spacelift.io/blog/statefulset-vs-deployment).

## Control plane components

The control plane is a collective term for many different components. 
Together, they provide everything needed to administer your cluster but not actually start and run containers.

![img.png](images/02/control-plane.png)

### API Server `kube-apiserver`
The API server is the control plane component that **exposes the Kubernetes REST API**. 
You’re using this API whenever you run a command with Kubectl or use a GUI to manage the cluster. 
You’ll lose management access to your cluster when the API server fails, but your workloads won’t necessarily be affected.

### Controller Manager (`kube-controller-manager`)
Much of Kubernetes is built upon the _controller pattern_.
A controller is a loop that continually monitors your cluster and performs actions when certain events occur.
The **controller manager oversees all the controllers in your cluster**. 
It starts their processes and ensures they’re operational the whole time that your cluster’s running.

#### Controller types

* _Node Controller_: Manages the worker nodes in your cluster, ensuring they are **healthy and available** to run your applications. 
* _Replication Controller_: Ensures that a specified **number of replicas of your pods** are running at all times, providing high availability and fault tolerance. 
* _Deployment Controller_: Manages the deployment of your applications, **allowing you to perform rolling updates and rollbacks with ease**. 
* _StatefulSet Controller_: Manages stateful applications that require persistent storage and stable network identities, such as databases. 
* _DaemonSet Controller_: Ensures that a copy of a pod runs on each node in your cluster, typically used for running daemons or agents. 
* _Job Controller_: Manages batch jobs that run to completion, such as data processing tasks. 
* _CronJob Controller_: Manages scheduled jobs that run at specific intervals, such as backups or reports.

### Scheduler (`kube-scheduler`)
The **scheduler is responsible for placing newly created Pods onto the Nodes in your cluster**. 
The scheduling process works by first filtering out Nodes that can’t host the Pod, and then scoring each eligible Node to identify the most suitable placement.
Nodes could be filtered out because of insufficient CPU or memory, inability to satisfy the Pod’s affinity rules, or other factors such as being cordoned for maintenance. 
The _scoring process_ prioritizes Pods that satisfy non-mandatory conditions like preferred affinities. 
If several Nodes appear to be equally suitable, Kubernetes will try to evenly distribute your Pods across them.

### Etcd
Etcd is a **distributed key-value storage system** used to store replicas of the cluster state on all nodes. 
The main role of etcd is to **hold every API object, including config values and sensitive data you store in `ConfigMaps` and `Secrets`**.
**Etcd is the most security-critical control plane component**. Successfully compromising it would permit full access to your Kubernetes data. 
It’s important that etcd receives adequate hardware resources, too, as any starvation can affect the performance and stability of your entire cluster.

### Cloud Controller Manager
The Cloud Controller Manager integrates Kubernetes with your cloud provider’s platform. 
It **facilitates interactions between your cluster and its outside environment**. 
This component is involved whenever Kubernetes objects change your cloud account, such as by provisioning a load balancer, adding a block storage volume, or creating a virtual machine to act as a Node.

## Node components

Nodes are the **physical or virtual machines that host the Pods in your cluster**. 
Although it’s possible to run a cluster with a single Node, production environments should include several so you can horizontally scale your resources and achieve high availability.

Nodes **join the cluster using a token issued by the control plane**. 
Once a Node is admitted, the control plane starts scheduling new Pods for it. 
Each Node runs several software components to start containers and maintain communication with the control plane.

The diagram below shows the architecture of a node:

![img.png](images/02/node_diagram.png)

### Kubelet
Kubelet is the Node-level process that acts as **the control plane’s agent**. 
It periodically checks in with the control plane to **report the state of the Node’s workloads**. 
The **control plane can contact Kubelet when it wants to schedule a new Pod** on the Node.

`Kubelet` is also responsible for **running Pod containers**. 
It pulls the images required by newly scheduled Pods and starts containers to produce the desired state. 
Once the containers are up, Kubelet monitors them to ensure they remain healthy.

Read more about Kubernetes [Image Pull Policy](https://spacelift.io/blog/kubernetes-imagepullpolicy) .

### Kube-Proxy
The kube-proxy component facilitates network communications between the Nodes in your cluster. 
It automatically **applies and maintains networking rules so that Pods exposed by Services are able to reach each other**. 
If kube-proxy fails, Pods on that Node won’t be reachable over the network.
Read more on Networking document

### Container runtime - Container Runtime Interface
Each Node requires a CRI-compatible runtime so it can start your containers.

The `containerd` runtime is the most popular option, but alternatives such as `CRI-O` and `Docker Engine` can be used instead. 
The runtime uses operating system features such as `cgroups` to achieve containerization.

## Kubernetes extensibility
Kubernetes is highly extensible, so you can customize it to suit your environment. 
Although the control plane and Node-level software stacks are the most important, 
several other aspects of the architecture are significant too.

### Networking - Container Network Interface
Kubernetes networking uses a **plugin-based approach**. 
A  CNI-compatible networking plugin must be installed **to allow Pods to reach each other**. 
Most popular Kubernetes distributions include a plugin for you, but you’ll have to manually
install a solution such as `Calico` or `Flannel` when you deploy a cluster from scratch.

### Storage
Storage provisioning can work very differently depending on your cloud provider. 
**Storage Classes** provide a consistent interface for accessing different types of storage in your workloads. 
You can add storage classes to save data to different platforms, 
such as a local volume on a Node’s filesystem or your cloud platform’s block storage volumes.

### Container registry
Kubernetes also has an **external dependency on a container registry**. 
You’ll need somewhere central to store your container images. 
You can run a registry inside your cluster, but this is not included with the default Kubernetes distribution.

## Custom functionality - Custom Resource Definitions
You can add your own Kubernetes abstractions with custom resource definitions (**CRDs**). 
CRDs extend the API with support for your own data structures.

You can **build the functionality around your CRDs by writing controllers and operators**. 

These facilitate advanced automated workflows, such as automatically provisioning 
a database when you add a PostgresDatabaseConnection object to your cluster.

They use the same fundamental concepts as built-in functionality: 
you author a control loop that watches for new objects and performs tasks when they occur.


## Kubernetes and security
Complexity and many moving parts create the potential for security problems. 
Hardening Kubernetes is a substantial topic: while the system purports to be production-ready, in practice, 
you need to take several manual actions to fully protect yourself.
Two main concerns to be implemented manually in a cluster are
### Etcd encryption
Enabling etcd encryption is one essential step. 
**Your cluster’s data isn’t encrypted by default**, so passwords and certificates in secrets are stored in plain text.

### Securing API server
It’s also important to secure the API server, avoid running other software on your Nodes, and ensure you use features 
like networking policies to fully isolate your workloads from each other. \
You can learn how to strengthen your cluster in our Kubernetes security guide.



