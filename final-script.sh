#!/bin/bash

# Variables
CLUSTER_NAME="demo-cluster"
TARGET_VERSION="1.23" # Update this to your final target version
NODEGROUPS=("commerce-prod-node" "netural-eks-spot" "prod-node-group")
STATEFULSETS=("statefulset1" "statefulset2")
VERSIONS=("1.22")

# Backup Helm releases
echo "Backing up Helm releases..."
helm ls --all-namespaces -o yaml > helm-releases-backup.yaml

# Review existing pods
echo "Listing existing pods..."
kubectl get pods --all-namespaces -o wide > pods-list.txt

# Upgrade control plane and add-ons
for VERSION in "${VERSIONS[@]}"; do
    echo "Upgrading EKS control plane to version $VERSION..."
    aws eks update-cluster-version --name $CLUSTER_NAME --kubernetes-version $VERSION
    aws eks wait cluster-active --name $CLUSTER_NAME

    echo "Upgrading add-ons..."
    aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --resolve-conflicts=overwrite
    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni

    aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name kube-proxy --resolve-conflicts=overwrite
    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name kube-proxy

    aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name coredns --resolve-conflicts=overwrite
    aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name coredns

    echo "Control plane and add-ons upgraded to version $VERSION."
done

# Upgrade node groups
for VERSION in "${VERSIONS[@]}"; do
    for NODEGROUP in "${NODEGROUPS[@]}"; do
        echo "Upgrading node group $NODEGROUP to version $VERSION..."
        aws eks update-nodegroup-version --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP
        aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP
        echo "Node group $NODEGROUP upgraded to version $VERSION."
    done
done

# Upgrade Helm releases
echo "Upgrading Helm releases..."
helm ls --all-namespaces -q | while read release; do
    echo "Upgrading Helm release $release..."
    helm upgrade --install $release $(helm get values $release -o json | jq -r .chart)
done

# Restart StatefulSets
for SET in "${STATEFULSETS[@]}"; do
    echo "Restarting StatefulSet $SET..."
    kubectl rollout restart statefulset $SET
    kubectl rollout status statefulset $SET
done

echo "EKS cluster upgrade complete to version $TARGET_VERSION."
