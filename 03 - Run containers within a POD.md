# 03 - Run containers within a pod

From: https://blog.esc.sh/kubernetes-containers-linux-processes/

## How Linux kernel run processes

In order to understand the way a POD runs a container in Kubernetes because

> A container running inside a POD is a process running in a Linux machine

hen you start a program on Linux, the OS creates a process. This process has a unique ID called PID (Process ID). Each process has its own memory, file descriptors, etc.

Install critcl 

apt install critcl


# Inspecting Linux Process Namespace and Cgroup of a Pod in a Kind Cluster (Using Podman)

## 🔍 Understanding the Setup

- **Kind** creates Kubernetes clusters **inside Docker containers** (even if you use Podman for other things).
- So, **even on a Podman-based system**, Kind uses Docker unless explicitly built with Podman backend (which is experimental and less common).
- Therefore, to inspect namespaces and cgroups of pods in Kind, you still need to inspect **the Docker container** that represents the Kind node.

---

## ✅ How to Proceed Without Docker CLI

### Option 1: Use Podman’s Docker Compatibility

This might not work out of the box because Podman and Docker manage different runtimes. But if you installed Docker at some point, try:

```bash
podman ps
```

If you **see Kind node containers**, you can interact with them using Podman.

---

### Option 2: Use `nerdctl` or Docker CLI in Container

If you can't use Podman to see Kind nodes, install `nerdctl` or the Docker CLI temporarily to interact with Docker:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

Then:

```bash
docker ps | grep kind
```

---

### Option 3: Inspect from the Host Using `nsenter` and `/proc`

If you prefer not to use Docker tools at all, you can **find the container PID from the host** and then inspect namespaces and cgroups like this:

#### 1. Find Kind node container PID:

```bash
ps aux | grep kind-control-plane
```

Or list containerd-shim processes and match to Kind pods:

```bash
ps -ef | grep containerd-shim
```

#### 2. Inspect Pod container PIDs via `crictl` (from the host):

```bash
crictl ps -a
crictl inspect <container-id> | jq '.info.pid'
```

#### 3. Use `nsenter` to enter namespaces:

```bash
sudo nsenter -t <pid> -m -u -i -n -p bash
```

You're now inside the same namespaces as the pod container process.

#### 4. Check current namespaces and cgroups:

```bash
ls -l /proc/self/ns/
cat /proc/self/cgroup
```

---
 
## 🛠️ Tools You Might Need

Make sure you have:

```bash
sudo apt install -y jq util-linux cri-tools
```

> `jq` for parsing JSON, `nsenter` from `util-linux`, and `crictl` from `cri-tools`.

---

## Sidecar containers

> Sidecar containers are the **secondary containers that run along with the main application** container within the same Pod. 

These containers are used to enhance or to extend the functionality of the primary app container by providing additional services, 
or functionality such as **logging, monitoring, security, or data synchronization**, without directly altering the primary application code.
 
### Containers type in a pod

![containser_types.png](images%2F03%2Fcontainser_types.png)

#### init containers
One or more init containers, which are **run before the app containers are started**.
Init containers are exactly like regular containers, except:
* Init containers always run to completion.
* Each init container must complete successfully before the next one starts.
* **do not support probes**
* have **dedicated resource** (cpu and mem) definition 
* When all of the init **containers have run to completion** in sequence, kubelet initializes the application containers for the Pod and 
  runs them as usual.If a Pod's **init container fails**, the kubelet repeatedly restarts that init container until it succeeds. 
  However, if the Pod has a `restartPolicy` of `Never`, and an init container fails during startup of that Pod, 
  Kubernetes treats the overall Pod as failed.
* init containers offer a mechanism to block or delay app container startup until a set of **preconditions** are met.

#### app container
is the main container application, if restarted, the entire pod will be restarted. 

Multiple app containers can run in parallel within the same pod, this is done when the 
the main application container requires other components or services to run.
 
#### sidecar container
 
* can be started, stopped, or restarted without affecting the main application container and other init containers.
* Sidecar containers run concurrently with the main application container and they are not stopped as the init containers 
* Unlike init containers, **sidecar containers support probes** to control their lifecycle.
* Sidecar containers can interact directly with the main application containers, because like init containers they always **share the same network, and can optionally also share volumes** (filesystems).

### Example 

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: alpine:latest
          command: ['sh', '-c', 'while true; do echo "logging" >> /opt/logs.txt; sleep 1; done']
          volumeMounts:
            - name: data
              mountPath: /opt
      initContainers:
        - name: logshipper
          image: alpine:latest
          restartPolicy: Always
          command: ['sh', '-c', 'tail -F /opt/logs.txt']
          volumeMounts:
            - name: data
              mountPath: /opt
      volumes:
        - name: data
          emptyDir: {}
```


![sidecar_logging_container.png](images%2F03%2Fsidecar_logging_container.png)

