# Offline Workshop

The following sections describe a workflow for running an offline Crossplane
workshop. Please note that [Setup](#setup) must be done while network is still
accessible.

## Setup

1. Pull `kind` image with required images pre-loaded.

```
docker pull hasheddan/cross-kind:v1.4.1-local
```

> NOTE: in the future, the `aws-cli-runtime` image will also be included.

Pre-loaded images include:
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

```
docker pull crossplane/provider-aws:v0.20.0
```

2. Download Helm charts.

```
helm repo add localstack-repo https://localstack.github.io/helm-charts
helm pull localstack-repo/localstack --version 0.3.4

helm repo add crossplane-stable https://charts.crossplane.io/stable
helm pull crossplane-stable/crossplane --version 1.4.1
```

3. Download `k8scr` CLI.

Use directions [here](https://github.com/hasheddan/k8scr#quickstart).

> NOTE: `k8scr` download will be updated such that building the binary will not
> be required. `go install` can be used for convenience today.

4. Download Crossplane CLI.

```
curl -sL https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh | sh
```

## Install

If all steps were followed correctly in [Setup](#setup), this and all following
sections should be able to be run without a network connection.

1. Create `kind` cluster with custom image.

```
kind create cluster --image hasheddan/cross-kind:v1.4.1-local
```

2. Install `k8scr-distribution`.

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


3. Install Crossplane.

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

4. Install Localstack.

```
helm install localstack ./localstack-0.3.4.tgz --set startServices="s3" --set image.pullPolicy=Never
```

4. Push `provider-aws:v0.20.0` to in-cluster registry.

```
kubectl k8scr push crossplane/provider-aws:v0.20.0
```

## Develop

1. Create `Configuration` manifests in `./package` directory.

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

2. Build `Configuration`.

```
cd configuration
kubectl crossplane build configuration --name getting-started
```

3. Push `Configuration`.

> NOTE: in the future, the docker load step should be able to be avoided.

```
docker load -i getting-started.xpkg
docker tag <image-id-from-previous-command> myorg/getting-started:v0.0.1

kubectl k8scr push myorg/getting-started:v0.0.1
```

4. Install `Configuration`.

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
