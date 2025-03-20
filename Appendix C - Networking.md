# Appendix C - Networking

https://learnk8s.io/kubernetes-services-and-load-balancing

> The following commands are based on a Kind cluster running on Ubuntu with the KIND load balancer running
> as explained in [Appendix - Local kb8 with Kind on WSL2.md](Appendix%20-%20Local%20kb8%20with%20Kind%20on%20WSL2.md)

## Create the sample application

Consider a two-tier application consisting of two tiers: the frontend tier, which is a web server that serves HTTP responses to browser requests, 
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

Today, most Kubernetes clusters rely on **CoreDNS**, an open source DNS server written in Go, to provide DNS services across the environment.
CoreDNS is deployed in a simple way: It **runs as a cluster-level Pod and handles DNS queries within the cluster from there**. 
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
This file specifies how DNS queries are resolved, including the nameservers to use and the search domains to help expand queries.

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




