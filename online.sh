#!/bin/bash
set -eE

# Online Steps

docker pull hasheddan/cross-kind:v1.4.1-local
docker pull crossplane/provider-aws:v0.20.0

helm repo add localstack-repo https://localstack.github.io/helm-charts || true
helm repo add crossplane-stable https://charts.crossplane.io/stable || true
helm repo update

helm pull localstack-repo/localstack --version 0.3.4
helm pull crossplane-stable/crossplane --version 1.4.1

go install github.com/hasheddan/k8scr/cmd/k8scr@latest
sudo mv ${GOPATH}/bin/k8scr /usr/local/bin/kubectl-k8scr

curl -sL https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh | sh

echo "\nYou can run offline now!"