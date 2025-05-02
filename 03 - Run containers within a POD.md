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

## ✅ Bonus: What You Can Automate

Would you like a Bash script to gather this info for a specific pod?
