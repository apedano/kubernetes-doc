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

A pod sends a packet to the ClusteIP Service

```bash
curl http://10.96.5.81:3000
```

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
iptables -t nat -L KUBE-SERVICES -n --line-numbers

#output
1  KUBE-SVC-NPX46M4PTMTKRN6Y  /* default/kubernetes:https cluster IP */ tcp dpt:443
2  KUBE-SVC-TCOU7JCQXEZGVUNU  /* kube-system/kube-dns:dns cluster IP */ udp dpt:53
3  KUBE-SVC-ERIFXISQEP7F7OF4  /* kube-system/kube-dns:dns-tcp cluster IP */ tcp dpt:53
4  KUBE-SVC-JD5MR3NA4I4DYORP  /* kube-system/kube-dns:metrics cluster IP */ tcp dpt:9153
5  KUBE-SVC-6R7RAWWNQI6ZLKMO  /* default/backend-service:backend cluster IP */ tcp dpt:3000
6  KUBE-NODEPORTS             /* kubernetes service nodeports;
```

The chain matching the destination IP:PORT is 5, having the cluster ip as target and 3000 as port

```bash
5  KUBE-SVC-6R7RAWWNQI6ZLKMO  /* default/backend-service:backend cluster IP */ tcp dpt:3000
```

Again the intercepted chain is 

```bash
iptables -t nat -L KUBE-SVC-6R7RAWWNQI6ZLKMO -n --line-numbers
1  KUBE-MARK-MASQ              /* default/backend-service:backend cluster IP */ tcp dpt:3000
2  KUBE-SEP-O3HWD4DESFNXEYL6   /* default/backend-service:backend -> 10.244.1.2:3000 */
3  KUBE-SEP-C2Y64IBVPH4YIBGX   /* default/backend-service:backend -> 10.244.1.3:3000 */
4  KUBE-SEP-MRYDKJV5U7PLF5ZN   /* default/backend-service:backend -> 10.244.1.4:3000 */
```

The first chain is `KUBE-MARK-MASQ`, which patches the source IP when the destination is external to the cluster,
which is not this case

The second is a certain number of **SEP service endpoint chain**

> One SEP chain is created for each `Endpoint` generated by the `Service`. The selection of the chain is based on probability and affinity to balance the traffic 

Suppose the one below is selected
```bash
iptables -t nat -L KUBE-SEP-O3HWD4DESFNXEYL6 -n --line-numbers
1    KUBE-MARK-MASQ    10.244.1.2    0.0.0.0/0    /* default/backend-service:backend */
2    DNAT                                         /* default/backend-service:backend */ tcp to:10.244.1.2:3000
```

This time the KUBE-MARK-MASK chain matches the source IP 10.244.1.2.
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






READ https://learnk8s.io/kubernetes-services-and-load-balancing#exposing-the-frontend-pods


