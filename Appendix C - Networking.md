# Appendix C - Networking

https://learnk8s.io/kubernetes-services-and-load-balancing

> The following commands are based on a Kind cluster running on Ubuntu with the KIND load balancer running
> as explained in [Appendix - Local kb8 with Kind on WSL2.md](Appendix%20-%20Local%20kb8%20with%20Kind%20on%20WSL2.md)

## Create the sample application

Consider a two-tier application consisting of two tiers: the frontend tier, which is a web server that serves HTTP
responses to browser requests,
and the backend tier, which is a stateful API containing a list of job titles.

### Init kind cluster

We will use kind with the two node cluster example in the config file

```bash
PS C:\projects\kubernetes-doc\config> kind create cluster --config .\my-two-nodes-cluster-config.yaml
```

### Deploy backend app

Now we can apply the [backend-deployment.yaml](config%2Fnetworking%2Fbackend-deployment.yaml) as

```bash
kubectl apply -f ./kube-config/networking/backend-deployment.yaml
```

```bash

> kubectl get pod -l app=backend -o wide

NAME                                  READY   STATUS    IP           NODE                       
backend-deployment-76cfdcfdd8-fdlsc   1/1     Running   10.244.1.2   my-two-node-cluster-worker 
```

The ip address assigned to the pod is `10.244.1.2`

### Expose backend app with `Service` of type `ClusterIp`

Now we expose the pod port inside the cluster to be accessible from other pods with a `Service`

```bash
kubectl apply -f ./kube-config/networking/backend-service.yaml 
```

```bash
kubectl get service
NAME              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S) 
backend-service   ClusterIP   10.96.51.94   <none>        3000/TCP
```

The service expose IP address `10.96.51.94:3000`

#### CoreDNS and `kube-dns` service for DNS `Service` name resolution

Today, most Kubernetes clusters rely on **CoreDNS**, an open source DNS server written in Go, to provide DNS services
across the environment.
CoreDNS is deployed in a simple way: It **runs as a cluster-level Pod and handles DNS queries within the cluster from
there**.
By default, the service is named `kube-dns` on the `kube-system` namespace.

```bash
kubectl get svc -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   PORT(S)               
kube-dns   ClusterIP   10.96.0.10   53/UDP,53/TCP,9153/TCP
```

When the `Service` is applied a DNS record pointing to the IP is created with the following format

`<service-name>.<namespace>.svc.cluster.local.`

In our example `backend-service.default.svc-cluster.local`

`Kubelet` configures each pod's `/etc/resolv.conf` file.
This file specifies how DNS queries are resolved, including the nameservers to use and the search domains to help expand
queries.

```bash
POD_NAME=$(kubectl get pods -l app=backend -o jsonpath='{.items[*].metadata.name}')
kubectl exec -it $POD_NAME  -- cat /etc/resolv.conf
nameserver 10.96.0.10 #the IP of the kube-dns
search default.svc.cluster.local svc.cluster.local cluster.local dns.podman
```

The `search` string makes every DNS name resolved against the string arguments, in order.
The first will match with the name of the created DNS name for the `Service`

We can test the DNS resolution with the following command

```bash
kubectl run curl-client --rm -i --tty --image=curlimages/curl -- /bin/sh

~ $ curl 10.96.51.94:3000
{"job":"Chief Unicorn Wrangler","pod":"backend-deployment-76cfdcfdd8-kbtql"}

~ $ curl backend-service.default.svc.cluster.local:3000
{"job":"Supreme Commander of Stuff","pod":"backend-deployment-76cfdcfdd8-kbtql"}
```

## `ClusterIP` Services and `kube-proxy`

As we know, pods are ephemeral, meaning that we cannot rely on stable IP rules
to route network traffic in or outside the cluster.

> We need stable IP forward rules hiding the pod's IP unreliability.

**On each cluster node** the `kube-proxy` runs as a `DaemonSet`, translating your Services into usable networking rules.

![service_creation_drawio.png](images%2Fnetworking%2Fservice_creation_drawio.png)

1) A new `Service` is committed to the master node via the _API server_
2) The _endpoint controller_ (monitored by the _controller manager_) evaluates the service selector, intercepting the
   pods
3) For each selected pod a new `Endpoint` (IP,port pair) is added to _ETCD_ and propagated to all nodes
4) `kube-proxy` deamon running on each node, watches (subscribes) to the change in _ETCD_
5) `kube-proxy` changes the IPtables rules onto the node linux kernel

However, other popular tools use different options like IPVS, eBPF, and nftables.

Regardless of the underlying technology,

> `kube-proxy` primarily sets up rules to instruct the kernel to rewrite the destination IP address from the service IP
> to the IP of one of the pods backing the service.

Let's see how this works in practice for IPTables.

### `kube-proxy` and IPTables

IPtables in general:
[Appendix D - Linux IPTables.md](Appendix%20D%20-%20Linux%20IPTables.md)

Among the available tables in `iptables`, Kubernetes uses **NAT** table

![iptable_nat_table.svg](images%2Fnetworking%2Fiptable_nat_table.svg)

Kubernetes uses custom chains:

- the main attached to **PREROUTING** is **KUBE-SERVICES**
    - `kube-proxy` attaches a service specific chains when a ClusterIP service is applied
    - As pods are added or removed from the service, `kube-proxy` dynamically updates these chains.
    - the traffic is DNAT (destination IP replaced) to the pod IP

## CASE 1 - POD to `ClusterIP` Service traffic

Make sure the backend deployment and the service are deployed to the cluster

[backend-deployment.yaml](config%2Fnetworking%2Fbackend-deployment.yaml)
[backend-service.yaml](config%2Fnetworking%2Fbackend-service.yaml)

### Create a pod in the kind cluster to call the backend svc

Get the service ip

```bash
$ kubectl get svc
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
backend-service             ClusterIP   10.96.91.147    <none>        3000/TCP       10m
...
```

Now we can create a pod and connect to its terminal

```bash
kubectl run curl-client --rm -i --tty \
--image=curlimages/curl -- /bin/sh
```

and send a packet to the ClusterIP Service

```bash
curl http://10.96.91.147:3000 
```

### Connect to a cluster node

We can connect to any node with the following

```bash
podman ps
```

And identify the name of the cluster's master node: `my-two-node-cluster-control-plane`
Now we connect to it

```bash
podman exec -it my-two-node-cluster-control-plane bash
```

We now have access to the iptables chains

### Analyse the iptables NAT table in the master node

The `kube-proxy` on the target worker node will start with the **PREROUTING** of the NAT iptable

```bash
iptables -t nat -L PREROUTING --line-numbers

#output
1  KUBE-SERVICES  all  anywhere      anywhere             /* kubernetes service portals */
2  DOCKER_OUTPUT  all  anywhere      host.minikube.internal
3  DOCKER         all  anywhere      anywhere             ADDRTYPE match dst-type LOCAL
```

The first line `KUBE-SERVICES` matches the target ip (`anywhere`),

```bash
Chain KUBE-SERVICES (2 references)
num  target     prot opt source               destination
1    KUBE-SVC-TCOU7JCQXEZGVUNU  17   --  0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:dns cluster IP */ udp dpt:53
2    KUBE-SVC-RMXBZCT6XVCXF3QP  6    --  0.0.0.0/0            10.96.91.147         /* default/backend-service:backend cluster IP */ tcp dpt:3000
3    KUBE-SVC-L2KBDCMJUD65WX3D  6    --  0.0.0.0/0            10.96.141.224        /* default/frontend-nodeport-service:frontend cluster IP */ tcp dpt:80
4    KUBE-SVC-NPX46M4PTMTKRN6Y  6    --  0.0.0.0/0            10.96.0.1            /* default/kubernetes:https cluster IP */ tcp dpt:443
5    KUBE-SVC-ERIFXISQEP7F7OF4  6    --  0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:53
6    KUBE-SVC-JD5MR3NA4I4DYORP  6    --  0.0.0.0/0            10.96.0.10           /* kube-system/kube-dns:metrics cluster IP */ tcp dpt:9153
7    KUBE-NODEPORTS  0    --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service nodeports; NOTE: this must be the last rule in this chain */ ADDRTYPE match dst-type LOCAL
```

The chain matching the destination IP:PORT `10.96.91.147:3000` is 2,
having `backend-service:backend cluster IP tcp dpt:3000`

Again the intercepted chain is

```bash
$ iiptables -t nat -L KUBE-SVC-RMXBZCT6XVCXF3QP -n --line-numbers

Chain KUBE-SVC-RMXBZCT6XVCXF3QP (1 references)
num  target prot opt source               destination
1    KUBE-MARK-MASQ             6    -- !10.244.0.0/16        10.96.91.147         /* default/backend-service:backend cluster IP */ tcp dpt:3000
2    KUBE-SEP-MP6GSFTQB7676C7X  0    --  0.0.0.0/0            0.0.0.0/0            /* default/backend-service:backend -> 10.244.1.3:3000 */ statistic mode random probability 0.50000000000
3    KUBE-SEP-TNKKKJMPBBOB5NOU  0    --  0.0.0.0/0            0.0.0.0/0            /* default/backend-service:backend -> 10.244.1.4:3000 */
```

The first chain is `KUBE-MARK-MASQ`, which patches the source IP when the destination is external to the cluster,
which is not this case

The next lines are **SEP service endpoint chain**

> One SEP chain is created for each `Endpoint` generated by the `Service`. The selection of the chain is based on
> probability and affinity to balance the traffic

in this case we have two SEP chains each linked to the POD ip(s), since the deployment has 2 replicas

Suppose the one below is selected

```bash
iptables -t nat -L KUBE-SEP-MP6GSFTQB7676C7X -n --line-numbers
Chain KUBE-SEP-MP6GSFTQB7676C7X (1 references)
num  target     prot opt      source               destination
1    KUBE-MARK-MASQ  0    --  10.244.1.3           0.0.0.0/0            /* default/backend-service:backend */
2    DNAT            6    --  0.0.0.0/0            0.0.0.0/0            /* default/backend-service:backend */ tcp to:10.244.1.3:3000
```

This time the KUBE-MARK-MASK chain matches the source IP 10.244.1.3 which is the pod ip Endpoint linked to the SEP chain
This is needed for **Hairpin NAT** explained below.

The **DNAT** rule changes the destination IP of the packet replacing it with the POD IP.
So the packet can be forwarded to the destination pod.

### Hairpin NAT - POD sending traffic to a Service it belongs to

Hairpin NAT, also known as NAT loopback or U-turn NAT, is a networking technique that allows a Pod within a Kubernetes
cluster to access its own Service IP address. Without special handling, this scenario can lead to routing problems
because the traffic originates and is destined for an IP address within the cluster's internal network, potentially on
the same node.

The `KUBE-MARK-MASQ` chain plays a crucial role in enabling Hairpin NAT in Kubernetes when using iptables mode. Here's
how it works in this context:

Example

The POD A sends a packet to the service it belongs, being delivered to either POD A or POD B

![hairpin_nat.drawio.png](images%2Fnetworking%2Fhairpin_nat.drawio.png)

The packet is sent

| SourceIP     | DestinationIP |
|--------------|---------------|
| `10.244.1.5` | `10.0.0.10`   |

The packet follows the chains

- node NAT table
- **PREROUTING** chain
- Services chain **KUBE-SERVICES**
- Service specific chain **KUBE-SVC-XXX**
- Service endpoint chain **KUBE-SEP-YYY**
- **KUBE-MARK-MASQ** chain applied if the Destination IP is the Service IP itself

The last chain does the following

**Marking the Packet**: The packet is marked with a special marker (typically 0x4000). This
mark signifies that this traffic needs to be **Source Network Address Translation (SNAT)** even though both the source
and destination are within the internal network.

| SourceIP     | DestinationIP | Mark     |
|--------------|---------------|----------|
| `10.244.1.5` | `10.0.0.10`   | `0x4000` |

**DNAT**: It will eventually be DNAT'ed (Destination NAT) to the IP address of one of the backend Pods (in this case,
potentially Pod A itself or another Pod on the same node).

| SourceIP     | DestinationIP                  | Mark     |
|--------------|--------------------------------|----------|
| `10.244.1.5` | `10.244.1.6` (or `10.244.1.5`) | `0x4000` |

Now the chains are:

- **KUBE-POSTROUTING** As the packet is about to leave the node's network stack

Here the **MASQUERADE** rule, looks for the 0x4000 mark set by **KUBE-MARK-MASQ**, will perform **SNAT** to the IP
address of the node itself.

| SourceIP      | DestinationIP | Mark     |
|---------------|---------------|----------|
| `10.16.123.0` | `10.244.1.6`  | `0x4000` |

Without the masquerade the packet would be discarded

**Internal Routing**: Now, the packet with the node's IP as the source and the destination Pod's IP can be correctly
routed within the node's internal network and reach the destination Pod.

**Return Traffic**:

Original returning packet

| SourceIP     | DestinationIP | Mark |
|--------------|---------------|------|
| `10.244.1.6` | `10.16.123.0` |      |

When the destination Pod (Pod B) responds, the traffic goes back to the node's IP address.
Kubernetes connection tracking (`conntrack`) keeps track of this connection,
and the **reverse NAT** (Source and Dest) is performed

| SourceIP                         | DestinationIP                     | Mark |
|----------------------------------|-----------------------------------|------|
| `10.0.0.10` (from original DNAT) | `10.244.1.6` (from original SNAT) |      |

## Case 2 - POD to `NodePort` Service traffic

### Deploy the frontend application and `NodePort` Service

Create the 3 replicas deployment called `frontend-deployment`
[frontend-deployment.yaml](config%2Fnetworking%2Ffrontend-deployment.yaml)

This time we expose it with a `NodePort` service because we want the deployment pods to
be **reachable from outside the cluster**.

[frontend-nodeport-service.yaml](config%2Fnetworking%2Ffrontend-nodeport-service.yaml)

Since the deployment has `replica: 3`, the service will intercept three `Endpoint`,
being generated by the master node on ETCD.

```bash
$ kubectl get svc
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
frontend-nodeport-service   NodePort    10.96.39.33     <none>        80:30000/TCP   2m10s

$ kubectl get Endpoints
NAME                        ENDPOINTS                                         AGE
frontend-nodeport-service   10.244.1.4:8080,10.244.1.5:8080,10.244.1.6:8080   5m3s
```

> This NodePort is open on all nodes in the cluster, not just the node where the pod is running.
> A port number is assigned to the service 30000 in the port range 30000-32767

### Make the kind claster accessible at the NodePort

Since we need to access the service from outside the Kind cluster we need to forse the Nodeport service
to have assigned a port which matches the port mapping in the kind cluster configuration.

In the NodePort use: `spec.ports[0].nodePort: 30000`
In the kind cluster use the

```bash
extraPortMappings:
- containerPort: 30000
  hostPort: 30000
  protocol: TCP
```

So, from outside the cluster (cmd line) we can execute `curl localhost:30000`

### iptables setting for NodePort traffic handling

| SourceIP    | DestinationIP       | Mark |
|-------------|---------------------|------|
| EXTERNAL_IP | `10.16.123.0:30000` |      |

As for the pod to service traffic, everything starts with the **PREROUTING** chanin of the nat table

```bash
$ iptables -t nat -L KUBE-SERVICES -n --line-numbers
Chain KUBE-SERVICES (2 references)
num  target     prot opt source               destination
...
7    KUBE-NODEPORTS  0    --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service nodeports; NOTE: this must be the last rule in this chain */ ADDRTYPE match dst-type LOCAL
```

This time the intercepted custom chain is the **KUBE-NODEPORTS**, the last being tested when a packet reaches the node.

We can filter what is set for the Nodeport port number

```bash
$ iptables -t nat -L KUBE-NODEPORTS -n -v --line-numbers | grep 30000
1        0     0 KUBE-EXT-L2KBDCMJUD65WX3D  6    --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/frontend-nodeport-service:frontend */ tcp dpt:32721
```

And the content of the chain is

```bash
iptables -t nat -L KUBE-EXT-L2KBDCMJUD65WX3D -n -v --line-numbers
Chain KUBE-EXT-L2KBDCMJUD65WX3D (1 references)
num   pkts bytes target     prot opt in     out     source               destination
1        0     0 KUBE-MARK-MASQ  0    --  *      *       0.0.0.0/0            0.0.0.0/0            /* masquerade traffic for default/frontend-nodeport-service:frontend external destinations */
2        0     0 KUBE-SVC-L2KBDCMJUD65WX3D  0    --  *      *       0.0.0.0/0            0.0.0.0/0
```

- The first chain `KUBE-MARK-MASQ` simply applies a mark to the packet (it will be used later)
- The second is a service chain `KUBE-SVC-L2KBDCMJUD65WX3D` with the same code as the `EXT` chain,
    - the chain contains the three balanced `SEP` chains, each for the endpoints (pods) of the deployment
        - each SEP chain applies `MARK` and then `DNAT` to the packet as explained in the case before

| SourceIP    | DestinationIP          | Mark     |
|-------------|------------------------|----------|
| EXTERNAL_IP | `10.244.1.4:8080` DNAT | `0x4000` |

- Then the **POSTROUTING** chain is called responsible of the `SNAT`
    - Here if the packet is marked SNAT is applied
    - The mark is removed

| SourceIP     | DestinationIP          | Mark |
|--------------|------------------------|------|
| NODE_IP SNAT | `10.244.1.4:8080` DNAT |      |  

In  the **return traffic**, the external IP is applied by the `conntrack` functionality of the node
as seen in the case before.

LOAD BALANCER


READ https://learnk8s.io/kubernetes-services-and-load-balancing#load-balancer-service


