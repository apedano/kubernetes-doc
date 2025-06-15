# Appendix C - Networking

<!-- TOC -->
* [Appendix C - Networking](#appendix-c---networking)
  * [Create the sample application](#create-the-sample-application)
    * [Init kind cluster](#init-kind-cluster)
    * [Deploy backend app](#deploy-backend-app)
    * [Expose backend app with `Service` of type `ClusterIp`](#expose-backend-app-with-service-of-type-clusterip)
      * [CoreDNS and `kube-dns` service for DNS `Service` name resolution](#coredns-and-kube-dns-service-for-dns-service-name-resolution)
  * [`ClusterIP` Services and `kube-proxy`](#clusterip-services-and-kube-proxy)
    * [`kube-proxy` and IPTables](#kube-proxy-and-iptables)
  * [CASE 1 - POD to `ClusterIP` Service traffic](#case-1---pod-to-clusterip-service-traffic)
    * [Create a pod in the kind cluster to call the backend svc](#create-a-pod-in-the-kind-cluster-to-call-the-backend-svc)
    * [Connect to a cluster node](#connect-to-a-cluster-node)
    * [Analyse the iptables NAT table in the master node](#analyse-the-iptables-nat-table-in-the-master-node)
    * [Hairpin NAT - POD sending traffic to a Service it belongs to](#hairpin-nat---pod-sending-traffic-to-a-service-it-belongs-to)
    * [Using headless Service to connect directly to pods](#using-headless-service-to-connect-directly-to-pods)
  * [Case 2 - POD to `NodePort` Service traffic](#case-2---pod-to-nodeport-service-traffic)
    * [Deploy the frontend application and `NodePort` Service](#deploy-the-frontend-application-and-nodeport-service)
    * [Make the kind claster accessible at the NodePort](#make-the-kind-claster-accessible-at-the-nodeport)
    * [iptables setting for NodePort traffic handling](#iptables-setting-for-nodeport-traffic-handling)
  * [Case 2 - POD to `LoadBalancer` Service traffic](#case-2---pod-to-loadbalancer-service-traffic)
    * [LB health checks](#lb-health-checks)
  * [Kubernetes `externalTrafficPolicy` Explained](#kubernetes-externaltrafficpolicy-explained)
  * [Values of `externalTrafficPolicy`](#values-of-externaltrafficpolicy)
    * [1. `Cluster` (default)](#1-cluster-default)
    * [2. `Local`](#2-local)
  * [Example YAML](#example-yaml)
  * [Expose traffic using NGINX Ingress](#expose-traffic-using-nginx-ingress)
    * [Create a kind cluster](#create-a-kind-cluster)
    * [Install Nginx controller](#install-nginx-controller)
    * [Deploy sample workload](#deploy-sample-workload)
    * [Deploy `Ingress`](#deploy-ingress)
    * [Test call](#test-call)
<!-- TOC -->

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
PS C:\projects\kubernetes-doc\config> kind create cluster --config .\my-two-nodes-cluster-for-statefulset.yaml
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


### Using headless Service to connect directly to pods

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Understanding_DNS_records_for_Service_objects.html#1142-using-headless-services-to-connect-to-pods-directly

[create-cluster.sh](config%2Fnetworking%2Fheadless%2Fcreate-cluster.sh)

Services expose a set of pods at a stable IP address. 
Each connection to that IP address is automatically distributed across its Endpoints.

> The headless Service configure the internal DNS to return the pod IPs instead of the service’s cluster IP

This allows direct POD addressing from external or pod-to-pod traffic.

For headless services, the cluster DNS returns not just a single A record pointing to the service’s cluster IP, 
but **multiple `A` records, one for each pod that’s part of the service**. 
Clients can therefore query the DNS to get the IPs of all the pods in the service.

By applying the Service in the file 

[workloads.yaml](config%2Fnetworking%2Fheadless%2Fworkloads.yaml)

we notice that

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-headless-service
spec:
  selector:
    app: my-headless-app
  clusterIP: None  # This makes it a headless service
```
The `none` value makes the cluster create multiple DNS record for each pod, instead of the typical single one.

We can interrogate the kube-dns service from within a random pod in the deployment.

This will return a separate DNS record for each pod.

```shell
root@LAPTOP-6ONT27E9:/home/pedaa00/kube-config/networking/headless# kubectl exec -it my-headless-deployment-6c7f5cc86-986bn -- nslookup my-headless-service.default.svc.cluster.local
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   my-headless-service.default.svc.cluster.local
Address: 10.244.0.13
Name:   my-headless-service.default.svc.cluster.local
Address: 10.244.0.11
Name:   my-headless-service.default.svc.cluster.local
Address: 10.244.0.12
```

Despite a normal ClusterIP service when the DNS call returns always the same service IP

```shell
/ # nslookup quote
Server:         10.96.0.10
Address:        10.96.0.10#53 //

Name:   quote.kiada.svc.cluster.local ##ClusterIP DNS name
Address: 10.96.161.97

/ # curl --verbose http://quote
*   Trying 10.96.161.97:80...
* Connected to quote (10.96.161.97) port 80 (#0)
```

The DNS lookup for the **headless service name returns every time one of the POD IP directly**. 

```shell
/ # while true; do curl http://quote-headless; done
This is the quote service running in pod quote-002
This is the quote service running in pod quote-001
This is the quote service running in pod quote-002
This is the quote service running in pod quote-canary
```

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
Packet from external network

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

This time no **SVC** chains are matched, so the intercepted custom chain is the **KUBE-NODEPORTS**, the last being tested when a packet reaches the node.

We can filter what is set for the Nodeport port number


```bash
$ iptables -t nat -L KUBE-NODEPORTS -n -v --line-numbers | grep 30000
1        0     0 KUBE-EXT-L2KBDCMJUD65WX3D  6    --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/frontend-nodeport-service:frontend */ tcp dpt:30000
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

- Then the **POSTROUTING** chain is called, it is responsible for the `SNAT`
    - Here if the packet is marked SNAT is applied
    - The mark is removed

| SourceIP     | DestinationIP          | Mark |
|--------------|------------------------|------|
| NODE_IP SNAT | `10.244.1.4:8080` DNAT |      |  

In  the **return traffic**, the external IP is applied by the `conntrack` functionality of the node
as seen in the case before.


## Case 2 - POD to `LoadBalancer` Service traffic

This is a third type of services which refers to a **third party component** running next to the cluster.
For example, we use `cloud-provider-kind` as load balancer service.

When the following is submitted the the API Server 

[load-balancer-test-app-config.yaml](config%2Fload-balancer-test-app-config.yaml)


```bash
 kubectl apply -f ./kube-config/load-balancer-test-app-config.yaml
pod/foo-app created
pod/bar-app created
service/foo-service created
```

When the service is applied an IP address is assigned by the LB itself

```bash
NAME                  TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
foo-service       LoadBalancer   10.96.91.224   10.89.0.7     5678:32591/TCP   27s
```
this applies to the port 5678 because it is the port specification in the service

```yaml
kind: Service
metadata:
  name: foo-service
spec:
  type: LoadBalancer
  selector:
    app: http-echo
  ports:
    - port: 5678 #port exposed by the LB
      targetPort: 8080 #port exposed by the pods
```
If we call the LB multiple times we will see balanced responses by the pods

```bash
#LB_IP will contain the External IP exposed by the LB
LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo $LB_IP #10.89.1.10 in our cluster

# should output foo and bar depending on the lb assigned pod 
for i in {1..10}; do  
  curl ${LB_IP}:5678 
done 
```

> Internally, a NodePort service is created at every node, so the traffic coming from the balancer 
> will be balanced among the NodePort services (if the selected node doesn't contain target pods, an extra hop is necesasry)

Then the traffic is routed by the `NodePort` inside the node as shown in the case before.

Let's see how the traffic is routed on the nodes

```bash
podman exec -it my-two-node-cluster-control-plane bash

root@my-two-node-cluster-control-plane:/# iptables -t nat -L KUBE-NODEPORTS -n -v --line-numbers
Chain KUBE-NODEPORTS (1 references)
num   pkts bytes target     prot opt in     out     source               destination
1        5   300 KUBE-EXT-L6225SIXICQL5TGT  6    --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/foo-service */ tcp dpt:32591
```

The **EXT** chain is the one matching the `32591` target port assigned to the `foo-service` LB service.

```bash
root@my-two-node-cluster-control-plane:/# iptables -t nat -L KUBE-NODEPORTS -n -v --line-numbers
Chain KUBE-NODEPORTS (1 references)
num   pkts bytes target     prot opt in     out     source               destination
1        5   300 KUBE-EXT-L6225SIXICQL5TGT  6    --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/foo-service */ tcp dpt:32591
root@my-two-node-cluster-control-plane:/# iptables -t nat -L KUBE-EXT-L6225SIXICQL5TGT -n -v --line-numbers
Chain KUBE-EXT-L6225SIXICQL5TGT (1 references)
num   pkts bytes target     prot opt in     out     source               destination
1        5   300 KUBE-MARK-MASQ  0    --  *      *       0.0.0.0/0            0.0.0.0/0            /* masquerade traffic for default/foo-service external destinations */
2        5   300 KUBE-SVC-L6225SIXICQL5TGT  0    --  *      *       0.0.0.0/0            0.0.0.0/0
root@my-two-node-cluster-control-plane:/# iptables -t nat -L KUBE-SVC-L6225SIXICQL5TGT -n -v --line-numbers
Chain KUBE-SVC-L6225SIXICQL5TGT (2 references)
num   pkts bytes target     prot opt in     out     source               destination
1        0     0 KUBE-MARK-MASQ  6    --  *      *      !10.244.0.0/16        10.96.91.224         /* default/foo-service cluster IP */ tcp dpt:5678
2        2   120 KUBE-SEP-DVOBJ7OJCOYILCLE  0    --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/foo-service -> 10.244.1.10:8080 */ statistic mode random probability 0.50000000000
3        3   180 KUBE-SEP-UNHXZGN7JLV6JRBI  0    --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/foo-service -> 10.244.1.9:8080 */
```

The SEP chains will be present in both cluster nodes in order to forward the traffic properly

### LB health checks

When you set `externalTrafficPolicy: Local`, Kubernetes assigns a `healthCheckNodePort` to verify the health of the service's nodes,
because it needs to forward traffic to those nodes having active pods for the service.

- If the node has a healthy pod running the service, it passes the check, and the load balancer routes traffic to it.

- If the node does not have active pods for the service, it fails the check, and traffic stops being sent to that node.

It does this by regularly performing health checks on the nodes.

These checks typically target a NodePort and happen every 60 seconds.


## Kubernetes `externalTrafficPolicy` Explained

In Kubernetes, the `externalTrafficPolicy` field is a setting used in **Service** resources of type `LoadBalancer` or `NodePort`. It controls how traffic from external clients is routed to the backend Pods.

## Values of `externalTrafficPolicy`

### 1. `Cluster` (default)
- External traffic is distributed **across all nodes** in the cluster, regardless of where the actual backend Pods are running.
- The traffic may be **routed internally** to nodes that do have the Pods.
- **Pros**: Better load distribution; can use all nodes in the cluster.
- **Cons**: The **source IP is lost** (NATed), so the Pods won't see the real client IP unless something like `proxy protocol` is used.

### 2. `Local`
- Traffic is only routed to nodes that **actually have the backend Pods** for the Service.
- **Source IP is preserved (no SNAT)**, which is useful for logging, firewalling, etc.
- **Pros**: Preserves client IP.
- **Cons**: Can lead to uneven load if Pods are not evenly spread across nodes; some requests might fail if a node receives traffic but has no Pods.

## Example YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
  externalTrafficPolicy: Local
```

## Expose traffic using NGINX Ingress

### Create a kind cluster

Execute
[create-cluster.sh](config%2Fnetworking%2Fingress2%2Fcreate-cluster.sh)

This configuration will expose port 80 and 443 on the host.
It’ll also add a node label so that the nginx-controller may use a node selector to target only this node.
If a kind configuration has multiple nodes, it’s essential to only bind ports 80 and 443 on the host for one node because port collision will occur otherwise.

Check the status of the node
```bash
kubectl get node --show-labels
NAME                                STATUS   ROLES           AGE   VERSION   LABELS
cluster-for-ingress-control-plane   Ready    control-plane   25s   v1.32.2   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,ingress-ready=true,kubernetes.io/arch=amd64,kubernetes.io/hostname=cluster-for-ingress-control-plane,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=
```

### Install Nginx controller

```shell
kubectl apply --filename https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
```

the command will install the controller on the `ingress-nginx` namespace. 
We can wait for the controller's pod to be ready 

```shell

kubectl wait --namespace ingress-nginx \
 --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
   --timeout=180s
```

We can now deploy on any namespace a simple application with the service of type `ClusterIp`

### Deploy sample workload

```shell
kubectl run hello \
--expose \
--image nginxdemos/hello:plain-text \
--port 80

pod/hello created
service hello created
```

### Deploy `Ingress`

We define a new Ingress from 

[hello-ingress.yaml](config%2Fnetworking%2Fingress2%2Fhello-ingress.yaml)

```yaml
    - host: hello.test.com
      http:
        paths:
          - pathType: ImplementationSpecific
            backend:
              service:
                name: hello
                port:
                  number: 80
```
where incoming calls with host `hello.test.com` will be forwarded to the `hello` service

Now we can deploy the `Ingress` element

```shell
kubectl apply -f hello-ingress.yaml
```
And chech the status

```shell

$ kubectl describe ingress hello

Name:             hello
Labels:           <none>
Namespace:        default
Address:          localhost
Ingress Class:    <none>
Default backend:  <default>
Rules:
  Host              Path  Backends
  ----              ----  --------
  hello.test.com    hello:80 (10.244.0.8:80)
Annotations:      <none>
Events:
  Type    Reason  Age                    From                      Message
  ----    ------  ----                   ----                      -------
  Normal  Sync    8m (x2 over 8m32s)     nginx-ingress-controller  Scheduled for sync
  Normal  Sync    7m36s (x2 over 7m36s)  nginx-ingress-controller  Scheduled for sync
```

### Test call

First we need to find the IP address of the node (running on podman) where the ingress is active

```bash
$ podman inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' cluster-for-ingress-control-plane
10.89.0.5
```

> The call to the `Ingress` must contain the host `hello.test.com` otherwise the proxy will not be intercepted

Therefore we need to add the resolution of the host on the local machine by adding the follwing to `etc/hosts`

`10.89.0.5 hello.test.com`

And, finally, we can make the call

```bash
$ curl hello.test.com

Server address: 10.244.0.8:80
Server name: hello
Date: 23/May/2025:08:18:36 +0000
URI: /
Request ID: de6ca3cd335b53abc14cd9e040aa29e3**
```