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

```yaml
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
```

```
kubectl apply -f k8scr-distribution.yaml
```

This will install a pod in the default namespace:
```
kubectl get pods
NAME    READY   STATUS    RESTARTS   AGE
k8scr   1/1     Running   0          9s
```

### 3. Install Crossplane.

```yaml
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

## Develop and verify a simple S3 Bucket

### 1. Install AWS-Provider and configure localstack


```
kubectl crossplane install provider crossplane/provider-aws:v0.20.0
```

```yaml
cat > "localstack.yaml" << EOF
---
# AWS credentials secret
apiVersion: v1
kind: Secret
metadata:
  name: localstack-creds
  namespace: crossplane-system
type: Opaque
data:
  # This is just test/test.
  credentials: W2RlZmF1bHRdCmF3c19hY2Nlc3Nfa2V5X2lkID0gdGVzdAphd3Nfc2VjcmV0X2FjY2Vzc19rZXkgPSB0ZXN0Cg==
---
# AWS ProviderConfig that references the secret credentials
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: example
spec:
  endpoint:
    hostnameImmutable: true
    url:
      type: Static
      static: http://localstack.default.svc.cluster.local:4566
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: localstack-creds
      key: credentials
EOF
```

```
kubectl apply -f localstack.yaml
secret/localstack-creds created
providerconfig.aws.crossplane.io/example created
```

You can check the new CRDs which are now available:
```
kubectl get crds | grep aws
activities.sfn.aws.crossplane.io                           2021-10-26T09:47:02Z
addresses.ec2.aws.crossplane.io                            2021-10-26T09:46:59Z
apimappings.apigatewayv2.aws.crossplane.io                 2021-10-26T09:47:00Z
apis.apigatewayv2.aws.crossplane.io                        2021-10-26T09:47:01Z
authorizers.apigatewayv2.aws.crossplane.io                 2021-10-26T09:47:02Z
backups.dynamodb.aws.crossplane.io                         2021-10-26T09:46:59Z
...
```

> Note: you need to enable the respective services in localstack first.
> Currently only S3 is enabled.

### 2. Create an S3 Bucket

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
    name: test-bucket
spec:
    forProvider:
        acl: public-read-write
        locationConstraint: us-east-1
    providerConfigRef:
        name: example
EOF
```

Check whether the bucket MR was created:
```
kubectl get bucket
NAME          READY   SYNCED   AGE
test-bucket   True    True     8s
```

Verify that the bucket was created in the localstack backend: 
```
kubectl run aws-cli-runtime --image=luebken/aws-cli-runtime:latest --image-pull-policy='Never'
kubectl exec --stdin --tty aws-cli-runtime -- /bin/bash

# configure the aws cli for localstack setup
# use test/test for key and secret and default for the rest
aws configure
...

# point to the right endpoint
aws --endpoint-url=http://localstack.default.svc.cluster.local:4566 s3 ls
2021-10-25 20:44:28 test-bucket
```

### 3. Upload and test a website

On `aws-cli-runtime`:

Create html and upload it to the bucket:
```
echo "<html>hello from crossplane</html>" > index.html
aws --endpoint-url=http://localstack.default.svc.cluster.local:4566 s3 cp index.html s3://test-bucket --acl public-read
upload: ./index.html to s3://test-bucket/index.html
```

Verify the bucket has the html file:
```
aws --endpoint-url=http://localstack.default.svc.cluster.local:4566 s3api head-object --bucket test-bucket --key index.html
{
"LastModified": "2021-10-21T11:52:01+00:00",
"ContentLength": 35,
"ETag": "\"b785e6dedf26b0acefc463b9f12a74df\"",
"ContentType": "text/html",
"Metadata": {}
}

curl localstack.default.svc.cluster.local:4566/test-bucket/index.html
<html>hello from crossplane</html>
```

## Develop a composition

In this next step we want to leverage Crossplane feature of compositions to
create a simplified version of a bucket which installs some guardrails which
developers don't need to reason about and allows for operations to switch the
implementation. 


### 1. Create a CompositeResourceDefinition

`definition.yaml`
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xmybuckets.database.example.org
spec:
  group: database.example.org
  names:
    kind: XMyBucket
    plural: xmybuckets
  claimNames:
    kind: MyBucket
    plural: mybuckets
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
                  bucketName:
                    type: string
                required:
                  - bucketName
```

```
kubectl apply -f definition.yaml
```

You can find this new CRD as part of the rest of CRDs:
```
kubectl get crds | grep xmybuckets
xmybuckets.database.example.org                            2021-10-26T12:59:27
```

### 2. Create a Composition

`composition.yaml`
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xmybuckets.aws.database.example.org
  labels:
    provider: aws
spec:
  compositeTypeRef:
    apiVersion: database.example.org/v1alpha1
    kind: XMyBucket
  resources:
    - name: s3bucket
      base:
        apiVersion: s3.aws.crossplane.io/v1beta1
        kind: Bucket
        spec:
          forProvider:
            acl: public-read-write
            locationConstraint: us-east-1
          providerConfigRef:
            name: example
      patches:
        - fromFieldPath: "spec.parameters.bucketName"
          toFieldPath: "metadata.name"
          transforms:
            - type: string
              string:
                fmt: "org-example-%s"
```


```
kubectl apply -f composition.yaml
```

```
kubectl get composition
NAME                                  AGE
xmybuckets.aws.database.example.org   22h
``` 


### 3. Create a claim

`claim.yaml`
```yaml
apiVersion: database.example.org/v1alpha1
kind: MyBucket
metadata:
  name: my-bucket
  namespace: default
spec:
  compositionSelector:
    matchLabels:
      provider: aws
  parameters:
    bucketName: test-bucket
```

```
kubectl apply -f claim.yaml
```

```
kubectl get mybucket
NAME        READY   CONNECTION-SECRET   AGE
my-bucket   True                        22h
```

## Develop a configuration

In this section we are going to bundle the definitions we have created
previously and ship and install them via a single configuration.

Delete the resources on the cluster:
```
kubectl delete -f claim.yaml
kubectl delete -f composition.yaml
kubectl delete -f definition.yaml
```

Move the previously created files into a `package` directory:
```
mkdir package; mv definition.yaml claim.yaml composition.yaml package/
```

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

```yaml
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
