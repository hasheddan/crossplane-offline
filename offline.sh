#!/bin/bash
set -eE

# Offline Steps

kind create cluster --image hasheddan/cross-kind:v1.4.1-local --wait 5m

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

cat > "crossplane-values.yaml" << EOF
image:
    repository: hasheddan/crossplane-local
    tag: v1.4.1
    pullPolicy: Never
args:
    - "--registry=k8scr.default"
EOF

helm install crossplane -n crossplane-system --create-namespace ./crossplane-1.4.1.tgz -f crossplane-values.yaml

helm install localstack ./localstack-0.3.4.tgz --set startServices="s3" --set image.pullPolicy=Never

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=localstack --timeout=30s

kubectl k8scr push crossplane/provider-aws:v0.20.0

kubectl crossplane install provider crossplane/provider-aws:v0.20.0

svn export https://github.com/crossplane/crossplane.git/trunk/docs crossplane-docs