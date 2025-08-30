# Appendix - kubectl commands

## Get resource

```bash
kubectl get <resource> -n <ns> <resource_name>

kubectl get <resource> --selector lbl1_key=lbl1_val,lbl2_key=lbl2_val
```

Example
```bash
kubectl get service -l app=myapp,environment=production

kubectl get svc -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   PORT(S)               
kube-dns   ClusterIP   10.96.0.10   53/UDP,53/TCP,9153/TCP


```
## Run terminals

### Execute a bash terminal from a pod

```bash
kubectl run curl-client --rm -i --tty --image=curlimages/curl -- /bin/sh
```


* `kubectl run` is the command to create and run a new pod.
* `curl-client` is the name you're assigning to the pod.
* `--rm` tells Kubernetes to delete the pod as soon as you exit the shell session. This is very useful for ephemeral debugging pods that you don't need to persist.
* `-i` (interactive): keeps stdin open, allowing you to interact with the shell running inside the pod.
* `--tty` (allocate a TTY): allocates a pseudo-TTY, which makes the shell inside the pod behave like a normal terminal. This is essential for interactive shell sessions.
* `--image=curlimages/curl`: specifies the container image to use for the pod. In this case, it's curlimages/curl, a lightweight Docker image containing the curl command-line tool.
* `-- /bin/sh`: 
  * The double dash (`--`) separates the kubectl flags from the command that will be executed inside the container.
  * `/bin/sh` is the command that will be executed when the container starts. It launches a basic shell within the container.

### Access Terminal on existing pod

```shell
$ kubectl exec -it <pod_name> -- sh
```



## Read logs from a pod or a selector

```shell
$ kubectl logs -f pod/shared-volume-pod -c reader
Hello from writer container

kubectl logs -f -l app=shared-volume -c reader
Hello from writer container
```
`-c` is the container name running inside the pod 
`-f` follows the log (same as tailing)
`-l` label to select pods

## Wait

### Wait for a deployment to be ready

```shell
kubectl wait deployment/my-app --for=condition=available --timeout=120s
```

```yaml
#after a deployment file has been applied
kubectl rollout status deploy my-app-v2 -w
```

