# Offline Workshop

The following sections describe a workflow for running an offline Crossplane
workshop with the AWS provider and [localstack](https://localstack.cloud/).
Please note that [Setup](#setup) must be done while network is still accessible.

## Setup

### 1. Pull `kind` image with required images pre-loaded.

For this setup we are using [kind](https://kind.sigs.k8s.io/) for running local
Kubernetes clusters with a dedicated image that has a set of images already included.

```
docker pull hasheddan/cross-kind:v1.4.1-local
```

The following images will be pre-loaded on the Kubernetes nodes:
- `hasheddan/crossplane-local:v1.4.1`: this image is a fork of
  `crossplane/crossplane:v1.4.1`, which includes the ability to trust a registry
  running in-cluster. It will be used when installing the Crossplane Helm chart.
- `crossplane/provider-aws-controller:v0.20.0`: this is the controller image for
  `provider-aws` v0.20.0. It will be used when `provider-aws` is installed
  (either directly or as a dependency of a `Configuration`).
- `localstack/localstack:latest`: this is the image used by the `localstack`
  Helm chart.
- `hasheddan/k8scr-distribution:latest`: this image is used to run a registry in
  the `kind` cluster that users can push `Configuration` image to.
- `luebken/aws-cli-runtime:latest`: a Debian based image providing a shell and the
  AWS CLI for manual interaction with localstack. 
  

In addition we will pull (and later push) an image for the Crossplane package manager to use:
```
docker pull crossplane/provider-aws:v0.20.0
```

> Note this open issue
> [crossplane/crossplane/#2647](https://github.com/crossplane/crossplane/issues/2647)
> which discusses also using node image cache for the package manager.

### 2. Download Helm charts.

There are two Helm charts which we need to prepare to install localstack and
crossplane itself: 

```
helm repo add localstack-repo https://localstack.github.io/helm-charts
helm pull localstack-repo/localstack --version 0.3.4

helm repo add crossplane-stable https://charts.crossplane.io/stable
helm pull crossplane-stable/crossplane --version 1.4.1
```

### 3. Download `k8scr` CLI.

For the Crossplane package manager we need to install an in-cluster container
registry. Use directions [here](https://github.com/hasheddan/k8scr#quickstart).

> NOTE: `k8scr` download will be updated such that building the binary will not
> be required. `go install` can be used for convenience today.

### 4. Download Crossplane CLI.

The Crossplane CLI extends kubectl with functionality to build, push, and
install Crossplane packages:

```
curl -sL https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh | sh
```

## Install

If all steps were followed correctly in [Setup](#setup), this and all following
sections should be able to be run without a network connection.

### 1. Create `kind` cluster with custom image.

```
kind create cluster --image hasheddan/cross-kind:v1.4.1-local
```

You can check the status by looking at the pods in the kube-system namespace:
```
kubectl get pods -n kube-system
NAME                                         READY   STATUS    RESTARTS   AGE
coredns-558bd4d5db-bd7xm                     1/1     Running   0          28s
coredns-558bd4d5db-w8lbd                     1/1     Running   0          28s
etcd-kind-control-plane                      1/1     Running   0          40s
kindnet-gzj86                                1/1     Running   0          28s
kube-apiserver-kind-control-plane            1/1     Running   0          40s
kube-controller-manager-kind-control-plane   1/1     Running   0          40s
kube-proxy-7hvgx                             1/1     Running   0          28s
kube-scheduler-kind-control-plane            1/1     Running   0          40s
```

You can check the pre-installed images by shelling into the Kubernetes node and
use
[crictl](https://github.com/kubernetes-sigs/cri-tools/blob/master/docs/crictl.md)
to list the images:

```
docker exec -it kind-control-plane /usr/local/bin/crictl images
IMAGE                                          TAG                  IMAGE ID            SIZE
docker.io/crossplane/provider-aws-controller   v0.20.0              57c08e6c0c61a       26.6MB
docker.io/hasheddan/crossplane-local           v1.4.1               06f9b487637e0       10.6MB
docker.io/hasheddan/k8scr-distribution         latest               f8b0c546cfd20       4.17MB
docker.io/kindest/kindnetd                     v20210616-5aea9f9e   05f2f0375e54a       38.3MB
docker.io/localstack/localstack                latest               e1cc5c887b0fa       357MB
docker.io/luebken/aws-cli-runtime              latest               a294931690e14       177MB
...
```

### 2. Install `k8scr-distribution`.

```
cat > "k8scr-distribution.yaml" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: k8scr
  labels:
    app: k8scr
spec:
  containers:
    - name: k8scr
      image: hasheddan/k8scr-distribution:latest
      imagePullPolicy: Never
---
apiVersion: v1
kind: Service
metadata:
  name: k8scr
spec:
  selector:
    app: k8scr
  ports:
    - name: reg
      protocol: TCP
      port: 80
      targetPort: 80
    - name: other
      protocol: TCP
      port: 443
      targetPort: 80
EOF

kubectl apply -f k8scr-distribution.yaml
```

This will install a pod in the default namespace:
```
kubectl get pods
NAME    READY   STATUS    RESTARTS   AGE
k8scr   1/1     Running   0          9s
```

### 3. Install Crossplane.

```
cat > "crossplane-values.yaml" << EOF
image:
    repository: hasheddan/crossplane-local
    tag: v1.4.1
    pullPolicy: Never
args:
    - "--registry=k8scr.default"
EOF
```

```
helm install crossplane -n crossplane-system --create-namespace ./crossplane-1.4.1.tgz -f crossplane-values.yaml
```

You can check the Crossplane pods are up and running:
```
kubectl get pods -n crossplane-system
NAME                                       READY   STATUS    RESTARTS   AGE
crossplane-556965f687-69gd8                1/1     Running   0          7s
crossplane-rbac-manager-55b5cb98f7-gzqkr   1/1     Running   0          7s
```


### 4. Install Localstack.

```
helm install localstack ./localstack-0.3.4.tgz --set startServices="s3" --set image.pullPolicy=Never
```

You can check the localstack pod and it's logs:
```
kubectl get pods
NAME                         READY   STATUS    RESTARTS   AGE
k8scr                        1/1     Running   0          3m34s
localstack-5d679bf9f-l72lm   1/1     Running   0          21s

kubectl logs $(kubectl get pods -l app.kubernetes.io/name=localstack -o name) -f
Waiting for all LocalStack services to be ready
2021-10-25 16:53:43,561 CRIT Supervisor is running as root.  Privileges were not dropped because no user is specified in the config file.  If you intend to run as root, you can set user=root in the config file to avoid this message.
2021-10-25 16:53:43,570 INFO supervisord started with pid 29
```

### 4. Push `provider-aws:v0.20.0` to in-cluster registry.

This will push the `provider-aws` package image into the `k8scr` registry:
```
kubectl k8scr push crossplane/provider-aws:v0.20.0
```

You can check the `k8scr` logs for activity on the container registry:
```
kubectl logs k8scr
2021/10/25 16:52:21 GET /v2
2021/10/25 16:52:22 HEAD /v2/crossplane/provider-aws/blobs/sha256:50e02ba0025001c951ee683c8a68960636b0fa6327fb88441fb3ba3223133fc6 404 BLOB_UNKNOWN Unknown blob
2021/10/25 16:52:22 POST /v2/crossplane/provider-aws/blobs/uploads
...
```

## Develop

### 1. Create `Configuration` manifests in `./package` directory.

`crossplane.yaml`
```yaml
apiVersion: meta.pkg.crossplane.io/v1
kind: Configuration
metadata:
  name: getting-started-with-aws
  annotations:
    guide: quickstart
    provider: aws
    vpc: default
spec:
  crossplane:
    version: ">=v1.0.0-0"
  dependsOn:
    - provider: crossplane/provider-aws
      version: "v0.20.0"
```

`definition.yaml`
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xpostgresqlinstances.database.example.org
spec:
  group: database.example.org
  names:
    kind: XPostgreSQLInstance
    plural: xpostgresqlinstances
  claimNames:
    kind: PostgreSQLInstance
    plural: postgresqlinstances
  connectionSecretKeys:
    - username
    - password
    - endpoint
    - port
  versions:
  - name: v1alpha1
    served: true
    referenceable: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              parameters:
                type: object
                properties:
                  storageGB:
                    type: integer
                required:
                  - storageGB
            required:
              - parameters
```

`composition.yaml`
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xpostgresqlinstances.aws.database.example.org
  labels:
    provider: aws
    guide: quickstart
    vpc: default
spec:
  writeConnectionSecretsToNamespace: crossplane-system
  compositeTypeRef:
    apiVersion: database.example.org/v1alpha1
    kind: XPostgreSQLInstance
  resources:
    - name: rdsinstance
      base:
        apiVersion: database.aws.crossplane.io/v1beta1
        kind: RDSInstance
        spec:
          forProvider:
            region: us-east-1
            dbInstanceClass: db.t2.small
            masterUsername: masteruser
            engine: postgres
            engineVersion: "12"
            skipFinalSnapshotBeforeDeletion: true
            publiclyAccessible: true
          writeConnectionSecretToRef:
            namespace: crossplane-system
      patches:
        - fromFieldPath: "metadata.uid"
          toFieldPath: "spec.writeConnectionSecretToRef.name"
          transforms:
            - type: string
              string:
                fmt: "%s-postgresql"
        - fromFieldPath: "spec.parameters.storageGB"
          toFieldPath: "spec.forProvider.allocatedStorage"
      connectionDetails:
        - fromConnectionSecretKey: username
        - fromConnectionSecretKey: password
        - fromConnectionSecretKey: endpoint
        - fromConnectionSecretKey: port
```

### 2. Build `Configuration`.

```
cd package
kubectl crossplane build configuration --name getting-started
```

### 3. Push `Configuration`.

> NOTE: in the future, the docker load step should be able to be avoided.

```
docker load -i getting-started.xpkg
docker tag <image-id-from-previous-command> myorg/getting-started:v0.0.1

kubectl k8scr push myorg/getting-started:v0.0.1
```

### 4. Install `Configuration`.

```
cat > "configuration.yaml" << EOF
apiVersion: pkg.crossplane.io/v1
kind: Configuration
metadata:
  name: getting-started
spec:
  package: myorg/getting-started:v0.0.1
  packagePullPolicy: IfNotPresent
  revisionActivationPolicy: Automatic
  revisionHistoryLimit: 1
EOF

kubectl apply -f configuration.yaml
```
