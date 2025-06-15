# 08 - StatefulSets

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/De
ploying_stateful_workloads_with_StatefulSets.html

## Difference with Deployment

With normal Deployment, each pod is considered ephemeral, when one is killed, it can
replaced directly without impacting the deployment functionality.

 In Kubernetes, you can use PersistentVolumes with the `ReadWriteMany` access mode to share data across multiple Pods. 
 However, in most cloud environments, the underlying storage technology typically only supports the `ReadWriteOnce` and `ReadOnlyMany` 
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
When you **scale down** the StatefulSet, the Pods are deleted, but the PersistentVolumeClaims are either **retained or deleted**, 
depending on the policy you configure in the StatefulSet.

## Governor service

The governor service is linked to the stateful set directly. It is of kind **headless**
[Appendix C - Networking.md](Appendix%20C%20-%20Networking.md#using-headless-service-to-connect-directly-to-pods)
in order to generate a separate DNS record for each numbered replica of the `sts`.
This way, a client can connect directly to one of the replicas via a DNS lookup (for example to connect to a master or replica 
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
And the sts  is

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

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Understanding_StatefulSet_behavior.html




