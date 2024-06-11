#!/bin/bash

# Variables
CLUSTER_NAME="your-cluster-name"
TARGET_VERSION="1.26" # Update this to your final target version
NODEGROUPS=("commerce-prod-node" "netural-eks-spot" "prod-node-group")
STATEFULSETS=("statefulset1" "statefulset2")
VERSIONS=("1.22" "1.23" "1.24" "1.25" "1.26")

# Log into EKS
login_eks() {
    echo "Logging into EKS..."
    aws eks update-kubeconfig --name $CLUSTER_NAME
    if [ $? -ne 0 ]; then
        echo "EKS login failed. Exiting."
        exit 1
    fi
    echo "Logged into EKS."
}

# Backup Helm releases
backup_helm_releases() {
    echo "Backing up Helm releases..."
    helm ls --all-namespaces -o yaml > helm-releases-backup.yaml
    if [ $? -eq 0 ]; then
        echo "Helm releases backed up successfully."
    else
        echo "Failed to backup Helm releases. Continuing."
    fi
}

# Review existing pods
review_pods() {
    echo "Listing existing pods..."
    kubectl get pods --all-namespaces -o wide > pods-list.txt
    if [ $? -eq 0 ]; then
        echo "Pods listed successfully."
    else
        echo "Failed to list pods. Continuing."
    fi
}

# Upgrade control plane and add-ons
upgrade_control_plane_and_addons() {
    for VERSION in "${VERSIONS[@]}"; do
        echo "Upgrading EKS control plane to version $VERSION..."
        aws eks update-cluster-version --name $CLUSTER_NAME --kubernetes-version $VERSION
        aws eks wait cluster-active --name $CLUSTER_NAME
        echo "Control plane upgraded to version $VERSION."

        echo "Upgrading add-ons..."
        aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --resolve-conflicts=overwrite
        aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni

        aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name kube-proxy --resolve-conflicts=overwrite
        aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name kube-proxy

        aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name coredns --resolve-conflicts=overwrite
        aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name coredns

        echo "Add-ons upgraded for control plane version $VERSION."
    done
}

# Upgrade node groups
upgrade_node_groups() {
    if [ ${#NODEGROUPS[@]} -eq 0 ]; then
        echo "No node groups to upgrade. Skipping."
        return
    fi

    for VERSION in "${VERSIONS[@]}"; do
        for NODEGROUP in "${NODEGROUPS[@]}"; do
            echo "Upgrading node group $NODEGROUP to version $VERSION..."
            aws eks update-nodegroup-version --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP
            aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP
            echo "Node group $NODEGROUP upgraded to version $VERSION."
        done
    done
}

# Upgrade Helm releases
upgrade_helm_releases() {
    echo "Upgrading Helm releases..."
    releases=$(helm ls --all-namespaces -q)
    if [ -z "$releases" ]; then
        echo "No Helm releases found. Skipping."
        return
    fi

    echo "$releases" | while read release; do
        echo "Upgrading Helm release $release..."
        helm upgrade --install $release $(helm get values $release -o json | jq -r .chart)
        if [ $? -eq 0 ]; then
            echo "Helm release $release upgraded successfully."
        else
            echo "Failed to upgrade Helm release $release. Continuing."
        fi
    done
}

# Restart StatefulSets
restart_statefulsets() {
    if [ ${#STATEFULSETS[@]} -eq 0 ]; then
        echo "No StatefulSets to restart. Skipping."
        return
    fi

    for SET in "${STATEFULSETS[@]}"; do
        echo "Restarting StatefulSet $SET..."
        kubectl rollout restart statefulset $SET
        kubectl rollout status statefulset $SET
        if [ $? -eq 0 ]; then
            echo "StatefulSet $SET restarted successfully."
        else
            echo "Failed to restart StatefulSet $SET. Continuing."
        fi
    done
}

# Main Script Execution
login_eks
backup_helm_releases
review_pods
upgrade_control_plane_and_addons
upgrade_node_groups
upgrade_helm_releases
restart_statefulsets

echo "EKS cluster upgrade complete to version $TARGET_VERSION."
