# 05 - Storage

https://rafay.co/the-kubernetes-current/dynamically-provisioning-persistent-volumes-with-kubernetes/

## Introduction - Storage clasees

### 1. File Storage (NAS – Network Attached Storage)

- **How it works**: Data is stored and accessed as complete **files** (with a hierarchy: folders, directories).
- **Protocol**: Uses file-level protocols like **NFS** (Linux/Unix) or **SMB/CIFS** (Windows).
- **Access**: Over a network – typically seen as a **shared folder**.
- **Management**: Managed **like a local file system** with permissions, file locking, etc.
- **Performance**: Can be slower compared to block storage due to file-system overhead.

**Best for**:

- Shared file access (home directories, office documents)
- File servers
- Media archives

---

### 2. Block Storage (SAN – Storage Area Network)

- **How it works**: Data is stored in **blocks**, like raw hard drives. Each block can be formatted with any file system
  the OS supports.
- **Protocol**: Uses block-level protocols like **iSCSI**, **Fibre Channel**.
- **Access**: Appears to the server as a physical hard drive; requires OS-level formatting.
- **Management**: More granular control over data placement and performance tuning.
- **Performance**: High-speed and low-latency; great for databases and transactional workloads.

**Best for**:

- Databases
- Virtual machine disks
- High-performance applications

---

### 3. Object Storage (Cloud-based or On-Prem)

- **How it works**: Data is stored as **objects** with metadata and a unique identifier, in a flat namespace (no
  folders).
- **Protocol/API**: Accessed via **HTTP-based APIs** (e.g., **S3**, **OpenStack Swift**).
- **Access**: Not mounted like a drive; accessed via apps or services via API.
- **Scalability**: Extremely scalable; ideal for unstructured data.
- **Performance**: Optimized for throughput and durability, not low-latency access.

**Best for**:

- Backup and archival
- Media files, images, videos
- Big data and analytics
- Cloud-native applications

---

### Summary Table

| Feature         | File (NAS)              | Block (SAN)          | Object (Cloud)             |
|-----------------|-------------------------|----------------------|----------------------------|
| Data Unit       | File                    | Block                | Object                     |
| Access Protocol | NFS, SMB                | iSCSI, Fibre Channel | HTTP/S (REST APIs)         |
| File System     | Managed by NAS          | Managed by Host OS   | No traditional file system |
| Performance     | Moderate                | High                 | Scalable, not low-latency  |
| Best Use Cases  | Shared files, user data | Databases, VMs       | Backup, media, web apps    |
| Scalability     | Limited by appliance    | Limited by SAN size  | Virtually unlimited        |

![storage_classes.PNG](images%2F04%2Fstorage_classes.PNG)

## Storage in Kubernetes: `PV` and `PVC`

Depending on the type of application, the Kubernetes cluster could deal with any of the classes specified above.

For instance, to run a database a block storage (AWS: EBS ElasticBlockStore, GCLOUD: GCEPD  GoogleComputeEnginePersistenceDisk) should be more appropriate. 
An object storage might be more suitable for store database backups (S3).

This requires that Kb8 should be able to interact with all those technologies, protocols and vendors,
meaning that a separate custom connector is needed to communicate with all of these. 

> Kubernetes creates a common interface to abstract the interaction with the storage and the way it is provided: **persistence volumes** and **persistence volume claim**.

All these different types of storage are abstracted as `PersistentVolume` `PV` instances inside the cluster, 
usually configured by cluster administrators and contains the vendor specific logic to interact with the storage. 

> - A **persistence volume** can be shared among several applications. 
> - Represents any piece of storage in cluster. 
> - That is persistent: exists beyond the lifecycle of the pod that is using it.

When a workload needs storage can define one or more **volume** of several types. 
A **volume** is an abstraction defining a **mount point** in the file system of the container.

A volume needs to be linked to a subpart of a `PV` via a `PersistentVolumeClaim` `PVC`, it is the
way to inform the cluster of a certain storage amount and type that a workload needs.

### `PV` lifecycle 

- **Provisioning**: system administrator creates storage chunck that are persistence volumes (block, NFS, distributes)

- **Binding (PVC)**: the developer asks for persistence storage request with PVC, binding to a persistence volume that was provisioned in the earlier stage (available in the storage pool). Here the storage amount and the access modes are defined. Every time a new PVC is created the master node controls storage pools for a matching PV with the PVC.

- **Using**: Use the claim in a pod as a volume. Once the PVC is submitted to the Kub API, the master node checks if the claim has been bound to a persistence volume. If yes, Kubernetes starts the pod using the volume.

- **Reclaiming**: once the user is done with their volume, the PVC can be deleted from Kubernetes which allows a reclaiming of the resources allocated  



https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Using_volumes.html
https://wangwei1237.github.io/Kubernetes-in-Action-Second-Edition/docs/Dynamic_provisioning_of_persistent_volumes.html
https://rafay.co/the-kubernetes-current/dynamically-provisioning-persistent-volumes-with-kubernetes/


