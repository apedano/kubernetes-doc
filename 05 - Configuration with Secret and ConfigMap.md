# 05 - Configuration with Secret and ConfigMap

## Configuring workload overriging `ENTRYPOINT` and `CMD`

> The two Docker directives `ENTRYPOINT` (the **command**) and `CMD` (the **arguments**) are used as startup commands for the base images running in a container

Example

```dockerfile
# Dockerfile
FROM node:12

ENTRYPOINT ["node", "app.js"]
CMD ["--listen-port", "8080"]
```

![entry_cmd.png](images%2F05%2Fentry_cmd.png)

We can override those by adding the `command` and `args` directive to the container section of a pod

```yaml
kind: Pod
spec: 
  containers:
    - name: example
      image: luksa/kiada:latest
      command: ["node", "test.js"]
      arguments: ["--listen-port", "9090"]
```

So that the main command from `node app.js --listen-port 8080` becomes `node app.js --listen-port 8080`

## Setting ENVIRONMENT varibles and placeholders

> We can set container environment variables, using placeholders to other variables only defined locally

```yaml
kind: Pod
metadata:
  name: kiada
spec:
  containers:
  - name: kiada
    image: luksa/kiada:0.4
    env:
    - name: POD_NAME
      value: kiada
    - name: INITIAL_STATUS_MESSAGE
      #Since NODE_VERSION is defined in the NodeJS image’s Dockerfile 
      #and not in the pod manifest, it can’t be resolved.
      value: My name is $(POD_NAME). I run NodeJS version $(NODE_VERSION).
```

Env vars defined by the image can be accessible using a shell command that will be executed inside the container and thus 
having access to all vars.

```yaml
containers:
- name: main
  image: alpine
  command:
  - sh
  - -c
  - 'echo "Hostname is $HOSTNAME."; sleep infinity'
```

## Injecting `ConfigMap` in a pod

### Injecting into container env vars

A ConfigMap can be injected for single entries of for all of them

Single entry:

```yaml
kind: Pod
...
spec:
  containers:
  - name: kiada
    env:
    - name: INITIAL_STATUS_MESSAGE
      valueFrom:
        configMapKeyRef:
          name: kiada-config
          key: status-message
          optional: true
    volumeMounts:
    - ...
```

In the previous listing, the reference to the config map key is marked as `optional` so that the container can be executed even if the config map or key is missing.

All config map

```yaml
kind: Pod
...
spec:
  containers:
  - name: kiada
    envFrom:
    - configMapRef:
        name: kiada-config
        optional: true
```
With this, the cm keys will be the var name with the corresponding value

We can apply with 

```shell
kubectl apply -f ./kube-config/secret-configmap/
```
And then

```shell
kubectl exec -it pod/pod-with-env-from-config-map -- env
...
env-var=This is the env var value
status-message=This is the status message value
...

kubectl exec -it pod/pod-with-single-value-from-config-map -- env
...
VARIABLE_FROM_CONFIG_MAP=This is the env var value
...

kubectl exec -it pod/pod-with-env -- env
...
INITIAL_STATUS_MESSAGE=My name is kiada. I run NodeJS version $(NODE_VERSION).
...
```
### Injecting a ConfigMap as volume

[config-map-as-volume-cm.yaml](config%2Fsecret-configmap%2Fconfig-map-as-volume-cm.yaml)
[pod-with-config-map-as-volume.yaml](config%2Fsecret-configmap%2Fpod-with-config-map-as-volume.yaml)
The ConfigMap can contain literals or `binaryData` (created when a `--from-file` option is used with a binary file) fields
In any case the configMap is mounted to the container file system and every entry key is a file name and the value is the file content.

```yaml
spec:
  containers:
    - name: busybox
      image: busybox
      command: ["sleep", "3600"]
      volumeMounts:
        - name: files
          mountPath: /data/
  volumes:
    - name: files
      configMap:
        name: config-map-as-volume
```


```shell
root@LAPTOP-6ONT27E9:/home/pedaa00# kubectl exec -it pod/pod-with-config-map-as-volume -- sh
/ # cd data/
/data # ls
data.bin       library.bin    text-file.txt
/data # cat text-file.txt
string file content
```



Chapter 9 config map and secrets

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Configuring_applications_using_ConfigMaps_Secrets_and_the_Downward_API.html