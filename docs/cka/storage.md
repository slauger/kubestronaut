# Storage (10%)

This domain covers Kubernetes storage concepts including PersistentVolumes, PersistentVolumeClaims, StorageClasses, and various volume types. While only 10% of the exam, storage questions are practical and require understanding the lifecycle of provisioning and consuming persistent storage.

## Key Concepts

### Volume Types

Kubernetes supports several volume types. The most commonly tested ones:

| Volume Type | Description | Persistent | Use Case |
|---|---|---|---|
| `emptyDir` | Temporary directory, deleted when pod is removed | No | Scratch space, cache, shared data between containers |
| `hostPath` | Mounts a file or directory from the host node | Yes (node-local) | Single-node testing, accessing host system files |
| `nfs` | NFS share mounted into the pod | Yes | Shared storage across pods and nodes |
| `persistentVolumeClaim` | References a PVC for dynamic/static provisioning | Yes | Production persistent storage |

#### emptyDir

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-data
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'Hello' > /data/message && sleep 3600"]
    volumeMounts:
    - name: shared-volume
      mountPath: /data
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /data/message && sleep 3600"]
    volumeMounts:
    - name: shared-volume
      mountPath: /data
  volumes:
  - name: shared-volume
    emptyDir: {}
```

#### hostPath

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: host-data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: host-data
    hostPath:
      path: /data/nginx
      type: DirectoryOrCreate
```

`hostPath` types: `DirectoryOrCreate`, `Directory`, `FileOrCreate`, `File`, `Socket`, `CharDevice`, `BlockDevice`.

!!! tip "Exam Tip"
    `hostPath` volumes are node-specific and not suitable for multi-node production use. They are commonly used in exam questions for simplicity. In production, use PersistentVolumes with a proper storage backend.

### PersistentVolumes (PV)

A PersistentVolume is a cluster-wide storage resource provisioned by an administrator or dynamically via a StorageClass.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-data
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/data
```

```yaml
# NFS PersistentVolume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Recycle
  nfs:
    server: nfs-server.example.com
    path: /exports/data
```

### PersistentVolumeClaims (PVC)

A PersistentVolumeClaim is a request for storage by a user. It binds to a matching PV.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-data
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: manual
```

#### Using a PVC in a Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-storage
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: persistent-storage
      mountPath: /usr/share/nginx/html
  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: pvc-data
```

### PV-PVC Binding Rules

A PVC binds to a PV when all of the following match:

- **Access modes**: PV must support the access modes requested by PVC
- **Capacity**: PV capacity must be >= PVC requested storage
- **StorageClass**: Must match (or both be empty for no class)
- **Selector**: If PVC has a selector, PV labels must match

```bash
# Check PV and PVC status
kubectl get pv
kubectl get pvc

# Troubleshoot binding issues
kubectl describe pvc pvc-data
```

### Access Modes

| Mode | Abbreviation | Description |
|---|---|---|
| ReadWriteOnce | RWO | Mounted as read-write by a single node |
| ReadOnlyMany | ROX | Mounted as read-only by many nodes |
| ReadWriteMany | RWX | Mounted as read-write by many nodes |
| ReadWriteOncePod | RWOP | Mounted as read-write by a single pod (Kubernetes 1.27+) |

!!! tip "Exam Tip"
    `ReadWriteOnce` (RWO) means the volume can be mounted by a single **node**, not a single pod. Multiple pods on the same node can still access a RWO volume.

### Reclaim Policies

| Policy | Behavior |
|---|---|
| **Retain** | PV is kept after PVC is deleted. Must be manually reclaimed. |
| **Delete** | PV and underlying storage are deleted when PVC is deleted. |
| **Recycle** | Basic scrub (`rm -rf /volume/*`). Deprecated. |

### StorageClasses

StorageClasses enable dynamic provisioning of PersistentVolumes. When a PVC references a StorageClass, the provisioner automatically creates a PV.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-storage
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```yaml
# PVC using a StorageClass for dynamic provisioning
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: fast-storage
```

```bash
# List StorageClasses
kubectl get storageclass

# Check the default StorageClass
kubectl get storageclass -o wide
# The default class has the annotation:
# storageclass.kubernetes.io/is-default-class: "true"
```

#### Volume Binding Modes

- **Immediate**: PV is provisioned as soon as the PVC is created
- **WaitForFirstConsumer**: PV provisioning is delayed until a pod using the PVC is scheduled (topology-aware)

### Volume Expansion

Expanding a PVC requires the StorageClass to have `allowVolumeExpansion: true`.

```bash
# Edit the PVC to request more storage
kubectl edit pvc dynamic-pvc
# Change spec.resources.requests.storage to a larger value
```

```yaml
# Or patch it
# kubectl patch pvc dynamic-pvc -p '{"spec":{"resources":{"requests":{"storage":"30Gi"}}}}'
```

!!! tip "Exam Tip"
    You can only expand a PVC, never shrink it. The StorageClass must have `allowVolumeExpansion: true`. Some storage backends require the pod using the PVC to be restarted for the filesystem to be resized.

### CSI Drivers

The Container Storage Interface (CSI) is the standard for exposing storage systems to Kubernetes. CSI drivers replace in-tree volume plugins.

```bash
# List installed CSI drivers
kubectl get csidrivers

# Check CSI node info
kubectl get csinodes
```

Common CSI drivers: AWS EBS CSI, GCP PD CSI, Azure Disk CSI, NFS CSI, Longhorn, Rook-Ceph.

## Practice Exercises

??? question "Exercise 1: Create a PV and PVC"
    Create a PersistentVolume named `task-pv` with 1Gi capacity, access mode `ReadWriteOnce`, hostPath `/mnt/task-data`, and storageClassName `manual`. Then create a PersistentVolumeClaim named `task-pvc` that requests 500Mi from this PV.

    ??? success "Solution"
        ```yaml
        # pv.yaml
        apiVersion: v1
        kind: PersistentVolume
        metadata:
          name: task-pv
        spec:
          capacity:
            storage: 1Gi
          accessModes:
          - ReadWriteOnce
          storageClassName: manual
          hostPath:
            path: /mnt/task-data
        ---
        # pvc.yaml
        apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          name: task-pvc
        spec:
          accessModes:
          - ReadWriteOnce
          resources:
            requests:
              storage: 500Mi
          storageClassName: manual
        ```

        ```bash
        kubectl apply -f pv.yaml
        kubectl apply -f pvc.yaml

        # Verify binding
        kubectl get pv task-pv
        kubectl get pvc task-pvc
        ```

??? question "Exercise 2: Mount a PVC in a Pod"
    Create a pod named `storage-pod` using image `nginx` that mounts the PVC `task-pvc` from the previous exercise at `/usr/share/nginx/html`.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: storage-pod
        spec:
          containers:
          - name: nginx
            image: nginx
            volumeMounts:
            - name: web-storage
              mountPath: /usr/share/nginx/html
          volumes:
          - name: web-storage
            persistentVolumeClaim:
              claimName: task-pvc
        ```

        ```bash
        kubectl apply -f storage-pod.yaml

        # Verify
        kubectl describe pod storage-pod | grep -A 5 Volumes
        ```

??? question "Exercise 3: Create a Pod with emptyDir for Sidecar Pattern"
    Create a pod named `sidecar-pod` with two containers. The first container (`writer`) uses image `busybox` and writes the current date to `/var/log/app.log` every 5 seconds. The second container (`reader`) uses image `busybox` and continuously tails `/var/log/app.log`. Both containers share an `emptyDir` volume mounted at `/var/log`.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: sidecar-pod
        spec:
          containers:
          - name: writer
            image: busybox
            command:
            - sh
            - -c
            - "while true; do date >> /var/log/app.log; sleep 5; done"
            volumeMounts:
            - name: log-volume
              mountPath: /var/log
          - name: reader
            image: busybox
            command:
            - sh
            - -c
            - "tail -f /var/log/app.log"
            volumeMounts:
            - name: log-volume
              mountPath: /var/log
          volumes:
          - name: log-volume
            emptyDir: {}
        ```

        ```bash
        kubectl apply -f sidecar-pod.yaml

        # Verify the reader is showing logs
        kubectl logs sidecar-pod -c reader
        ```

??? question "Exercise 4: Expand a PersistentVolumeClaim"
    Given an existing PVC named `app-data` backed by a StorageClass with `allowVolumeExpansion: true`, expand it from 5Gi to 10Gi.

    ??? success "Solution"
        ```bash
        # Option 1: Edit directly
        kubectl edit pvc app-data
        # Change spec.resources.requests.storage from 5Gi to 10Gi

        # Option 2: Patch
        kubectl patch pvc app-data -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'

        # Verify
        kubectl get pvc app-data
        # The CAPACITY column may still show 5Gi until the pod restarts
        # Check conditions for resize status
        kubectl describe pvc app-data
        ```

??? question "Exercise 5: Troubleshoot a PVC Stuck in Pending"
    A PVC named `pending-pvc` is stuck in `Pending` status. Identify and fix the issue.

    ??? success "Solution"
        ```bash
        # Check PVC details
        kubectl describe pvc pending-pvc

        # Common reasons for Pending PVC:
        # 1. No matching PV exists (check access modes, capacity, storageClassName)
        kubectl get pv

        # 2. StorageClass does not exist or has no provisioner
        kubectl get storageclass

        # 3. VolumeBindingMode is WaitForFirstConsumer (no pod is using it yet)
        kubectl get storageclass -o yaml | grep volumeBindingMode

        # Fix depends on the root cause:
        # - Create a matching PV if none exists
        # - Fix StorageClass name in PVC spec
        # - Create a pod that uses the PVC to trigger WaitForFirstConsumer binding
        # - Ensure PV access modes and capacity match PVC requirements
        ```

## Relevant Documentation

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)
- [CSI Drivers](https://kubernetes.io/docs/concepts/storage/volumes/#csi)
- [Configure a Pod to Use a PersistentVolume](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)
