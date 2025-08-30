# 09 - StatefulSets



## Difference with Deployment

With normal Deployment, each pod is considered ephemeral, when one is killed, it can
replaced directly without impacting the deployment functionality.

In Kubernetes, you can use PersistentVolumes with the `ReadWriteMany` access mode to share data across multiple Pods.
However, in most cloud environments, the underlying storage technology typically only supports the `ReadWriteOnce`
and `ReadOnlyMany`
access modes, not `ReadWriteMany`, meaning you can’t mount the volume on multiple nodes in read/write mode.
Therefore, Pods on different nodes can’t read and write to the same PersistentVolume.

> **All Pods from a Deployment use the same PersistentVolumeClaim** and PersistentVolume

> When we create a ClusterIP Service to expose a Deployment **all the traffic is directed
> to the ClusterIP IP** address within the cluster and distributed among the Pod replicas.

![15.1.png](images%2Fstatefulsets%2F15.1.png)

## Use case: MongoDB

For instance, a MongoDB cluster with master/slave replica has the following needs
that a Deployment cannot fulfill

* each **Pod has its own PersistentVolume**
* each **Pod is addressable** by its own address
* when a Pod is deleted the new Pod receives the **same address and PV**

### Use separate deployments

A solution might be to use separate Deployments and Services for each cluster replica.

![15.2.png](images%2Fstatefulsets%2F15.2.png)

The deployment specfic services make sure that **each replica is addressable separately**.
An additional service is needed to **intercept all pods in the cluster for the client connections**.

This **solution is difficult to scale**.

### Solution via StatefulSet

> When an application deployed with a StatefulSet has a pod replaced,
> it is **given the same network identity and state as the replaced instance**.

The Pods created from a StatefulSet aren't exact copies of each other, as is the case with Deployments,
because **each Pod points to a different set of PersistentVolumeClaims**.

**Each Pod is given a unique ordinal number, as is each PersistentVolumeClaim**.
When a StatefulSet Pod is deleted and recreated, it’s given the same name and PV as the Pod it replaced.

This makes the replicas stateful.

![15.4.png](images%2Fstatefulsets%2F15.4.png)

When you create a **StatefulSet replicas are created sequencially**: only the first Pod is created initially.
Then the StatefulSet controller waits until the Pod is ready before creating the next one.

A StatefulSet can be **scaled** just like a Deployment.
When you scale a StatefulSet up, new Pods and PersistentVolumeClaims are created from their respective templates.
When you **scale down** the StatefulSet, the Pods are deleted, but the PersistentVolumeClaims are either **retained or
deleted**,
depending on the policy you configure in the StatefulSet.

## Governor service

The governor service is linked to the stateful set directly. It is of kind **headless**
[Appendix C - Networking.md](Appendix%20C%20-%20Networking.md#using-headless-service-to-connect-directly-to-pods)
in order to generate a separate DNS record for each numbered replica of the `sts`.
This way, a client can connect directly to one of the replicas via a DNS lookup (for example to connect to a master or
replica
node of a DB cluster)

## Busybox example

We can see this in action by applying the following file

[headless_service_statefulset.yaml](config%2Fstatefulsets%2Fheadless_service_statefulset.yaml)

this has a governors headless service

```yaml
kind: Service
metadata:
  name: busybox-headless
  labels:
    app: busybox
spec:
  clusterIP: None  # Headless service
  selector:
    app: busybox #same in the sts
```

And the sts is

```yaml
kind: StatefulSet
metadata:
  name: busybox
spec:
  #the name of the headless service
  serviceName: "busybox-headless"
  replicas: 3
  selector:
    matchLabels:
      app: busybox
...
template:
  spec:
    volumeMounts:
      #each pod will have its own PVC
      - name: data
        mountPath: /data
    ...
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
```

This configuration will lead to the following structure

![stateful_set_headless_service.drawio.png](images%2Fstatefulsets%2Fstateful_set_headless_service.drawio.png)

The following workloads will be created:

```yaml
### POD
$ kubectl get pod -o name
pod/busybox-0
pod/busybox-1
pod/busybox-2
  ### PVC
$ kubectl get pvc -o name
persistentvolumeclaim/data-busybox-0
persistentvolumeclaim/data-busybox-1
persistentvolumeclaim/data-busybox-2
```

The service will be stored in the DNS db with the following name structure:

`<service_name>.<namespace>.svc.cluster.local`

So it will be

`busybox-headless.default.svc.cluster.local`

If we try the **DNS name resolution we will get the POD IP**

```shell
#from a pod of the sts <busybox-0>
$ kubectl exec -it busybox-0 -- sh
/ #
/ # nslookup busybox-headless.default.svc.cluster.local
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   busybox-headless.default.svc.cluster.local
Address: 10.244.0.8
Name:   busybox-headless.default.svc.cluster.local
Address: 10.244.0.6
Name:   busybox-headless.default.svc.cluster.local
Address: 10.244.0.10
```

Each resolution request will return a different IP

Additional specific `AAA` records will be generated with the format

`<pod_name>.<service_name>.<namespace>.svc.cluster.local`

so

`busybox-0.busybox-headless.default.svc.cluster.local`
`busybox-1.busybox-headless.default.svc.cluster.local`
`busybox-2.busybox-headless.default.svc.cluster.local`

```shell
$ kubectl exec -it busybox-0 -- sh

/ # nslookup busybox-1.busybox-headless.default.svc.cluster.local
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   busybox-0.busybox-headless.default.svc.cluster.local
Address: 10.244.0.8
```

## Missing POD replacement

If a pod is deleted

```shell
$ kubectl delete po busybox-1
pod "busybox-1" deleted
```

The stateful set controller replaces the missing pod with a new one
with the **same name and the same pvc attached**

```shell
kubectl describe sts/busybox
....

Events:
  Type    Reason            Age                 From                    Message
  ----    ------            ----                ----                    -------
  ...
  Normal  SuccessfulCreate  28s (x2 over 3m3s)  statefulset-controller  create Pod busybox-1 in StatefulSet busybox successful
```

> Even though the IP address will be different **the DNS record created by the headless service
will guarantee that the DNS resolution will remain**.

> In general, this new Pod can be **scheduled to any cluster node** if the `PersistentVolume` bound to
> the `PersistentVolumeClaim`
> represents a network-attached volume and not a local volume. If the volume is local to the node, **the Pod is always
scheduled to this node**.

## Scaling a Statefulset

### Scaling down

When the `replica` value of the stateful set is reduced the **pod with the highest values is removed** together with
the linked resources

```shell
$ kubectl scale sts busybox --replicas 1

kubectl describe sts/busybox
....

Events:
  Type    Reason            Age                 From                    Message
  ----    ------            ----                ----                    -------
  ...
 Normal  SuccessfulDelete  16s                statefulset-controller  delete Pod busybox-2 in StatefulSet busybox successful
 Normal  SuccessfulDelete  4s                 statefulset-controller  delete Pod busybox-1 in StatefulSet busybox successful
```

The #2 pod is deleted first and then the #1, since pod changes happen in ordered sequence.

> The PVCs are preserved when replica is scaled down by **default**. It can be changed
> with `persistentVolumeClaimRetentionPolicy` config

```shell
kubectl get pvc -l app=busybox
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-busybox-0   Bound    pvc-7d727039-dc7e-488b-a6b9-ad77f5e4788c   256Mi      RWO            standard       <unset>                 39m
data-busybox-1   Bound    pvc-8da40be7-b3cb-4782-b16a-e74ef0ce1e8b   256Mi      RWO            standard       <unset>                 38m
data-busybox-2   Bound    pvc-f5f5f812-ed5d-4dad-8343-a0785da36cb2   256Mi      RWO            standard       <unset>                 38m
```

This is because deleting a claim **result in data loss**.

#### `persistentVolumeClaimRetentionPolicy` configuration

The `whenScaled` determines the behavior when the sts is scaled down
The `whenDeleted` determines the behavior when the sts is deleted to avoid data loss.

```yaml
spec:
  persistentVolumeClaimRetentionPolicy:
    whenScaled: Delete
    whenDeleted: Retain
```

### Scaling up

The scale up increases the sts resource counter, increasing the highest value.
If there are PVCs available for the counter to be generated it will be attached

![15.6.png](images%2Fstatefulsets%2F15.6.png)

```shell
$ kubectl scale sts busybox --replicas 3
statefulset.apps/busybox scaled

$ kubectl get pods -l app=busybox
NAME        READY   STATUS    RESTARTS   AGE
busybox-0   1/1     Running   0          51m
busybox-1   1/1     Running   0          18s
busybox-2   1/1     Running   0          16s

$ kubectl get pvc -l app=busybox
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-busybox-0   Bound    pvc-7d727039-dc7e-488b-a6b9-ad77f5e4788c   256Mi      RWO            standard       <unset>                 51m
data-busybox-1   Bound    pvc-8da40be7-b3cb-4782-b16a-e74ef0ce1e8b   256Mi      RWO            standard       <unset>                 51m
data-busybox-2   Bound    pvc-f5f5f812-ed5d-4dad-8343-a0785da36cb2   256Mi      RWO            standard       <unset>                 51m
root@LAPTOP-6ONT27E9:/home/pedaa00/kube-config/statefulsets#
```

We see that the same PVC are reused for replica #1 and #2

## Using the `podManagementPolicy` Pod management policy

Depending on the application running in the sts, it might be needed to start replicas in order.
On example is when, for instance, the replica nodes of DB cluster need to be added only when the master is ready
to accept new replicas.
We can control this with the `podManagementPolicy` configuration

| Value        | Description                                                                                                                                                                                                                                                                                                                                                                                                 |
|--------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `OrderedReady` | Pods are created one at a time in ascending order. After creating each Pod, the controller waits until the Pod is ready before creating the next Pod. The same process is used when scaling up and replacing Pods when they’re deleted or their nodes fail. When scaling down, the Pods are deleted in reverse order. The controller waits until each deleted Pod is finished before deleting the next one. |
| `Parallel`     | All Pods are created and deleted at the same time. The controller doesn’t wait for individual Pods to be ready.                                                                                                                                                                                                                                                                                             |


## Update strategies

After deployment update strategies....
https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Updating_a_StatefulSet.html
