# 04 - Mounting volumes in containers

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Introducing_volumes.html

## Volume - Persisting data after container restart

When a pod container starts, the files in its filesystem are those **that were added to its container image during build
time**.
The process running in the container can then modify those files or create new ones. **When the container is terminated
and restarted, all changes it made to its files are lost**, because the previous container is not really restarted, but
completely replaced.
Although this may be okay for some types of applications, others may need the filesystem or at least part of it to be
preserved on restart.

To make data persistent **after container restart** a **volume** can be mounted
to the container file system.

> Like containers, volumes aren’t top-level resources like pods or nodes, but are a component within the pod and thus
> share its lifecycle. As the following figure shows, a volume is defined at the pod level and then mounted at the
> desired
> location in the container.

![7.2.jpg](images%2F04%2F7.2.jpg)

The lifecycle of a volume is tied to the lifecycle of the entire pod and is independent of the lifecycle of the
container in which it is mounted. Due to this fact, volumes are also used to persist data across container restarts.

![volume_container_restart.png](images%2F04%2Fvolume_container_restart.png)

More containers in a pod can share one volume with multiple **modes** (`read-write`, `read-only`) and
it can be mounted on different mount points inside each container's file system

![volume_multiple_containers.png](images%2F04%2Fvolume_multiple_containers.png)

## Persistent storage - Persisting data after pod restart

As the following figure shows, a pod volume can map to persistent storage outside the pod.
In this case, the file directory representing the volume isn’t a local file directory that persists data only for the
duration of the pod,
but is instead a mount to an existing, typically network-attached storage volume (NAS) whose lifecycle isn’t tied to any
pod. The data stored in the volume is thus persistent and can be used by the application even after the pod it runs in
is replaced with a new pod running on a different worker node.

![volume_from_storage.png](images%2F04%2Fvolume_from_storage.png)

### Volume types

| Name                                                                                                                                                                                                                            | Description                                                                                                                                                                            |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `emptyDir`                                                                                                                                                                                                                      | A simple directory created just before the pod starts and is initially empty - hence the name.                                                                                         |
| `hostPath`                                                                                                                                                                                                                      | Used for mounting files from the worker node’s filesystem into the pod                                                                                                                 |
| `gcePersistentDisk` (Google Compute Engine Persistent Disk)<br/>`awsElasticBlockStore` (Amazon Web Services Elastic Block Store), <br/>`azureFile` (Microsoft Azure File Service), <br/>`azureDisk` (Microsoft Azure Data Disk) | Used for mounting cloud provider-specific storage.                                                                                                                                     |
| `cephfs`, `cinder`, `fc`, `flexVolume`, `flocker`, `glusterfs`, `iscsi`, `portworxVolume`, `quobyte`, `rbd`, `scaleIO`, `storageos`, `photonPersistentDisk`, `vsphereVolume`                                                    | Used for mounting other types of network storage.                                                                                                                                      |
| `configMap`, `secret`, `downwardAPI`                                                                                                                                                                                            | Special types of volumes used to expose information about the pod and other Kubernetes objects through files. They are typically used to configure the application running in the pod. |
| `persistentVolumeClaim`                                                                                                                                                                                                         | A reference to a `PVC` that claim storage from the `PV` abstraction of actual storage class                                                                                            |
| `csi`                                                                                                                                                                                                                              | Pluggable storage via the **Container Storage Interface** with a, potentially user defined, driver. During pod setup, the CSI driver is called to attach the volume to the pod.        |


## The `emptyDir` volume

The volume is a simple directory mounted on each associated container and can be used to share data among pod's containers.

[shared-empty-dir-pod.yaml](config%2Fvolumes%2Fshared-empty-dir-pod.yaml)

```yaml
kind: Pod
...
spec:
  volumes:
    - name: shared-data
      emptyDir: {}
  containers:
    - name: writer
      ...
      args:
        - echo "Hello from writer container" > /data-writer/message.txt;
          sleep 3600;
      volumeMounts:
        - name: shared-data
          #the mount point does not have to be the same as the one on the reader container
          #bacuase it is local in the container file system
          mountPath: /data-writer

    - name: reader
      args:
        - cat /data/message.txt || echo "File not found";
          sleep 3600;
      volumeMounts:
        - name: shared-data
          mountPath: /data
```

The following configuration is supported

```yaml

pec:
  volumes:
    - name: shared-data
      emptyDir:
        medium: Memory
        sizeLimit: 10Mi
```

- `medium`: by default, the directory is created on one of the node’s disks. `Memory`, uses `tmpfs`, a virtual memory filesystem where the files are kept in memory.
- `sizeLimit`: no comment

https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Accessing_files_on_the_worker_nodes_filesystem.html

Chapter 9 config map and secrets