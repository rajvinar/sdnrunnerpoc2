#!/bin/bash

set -euxo pipefail

# Usage function to display help
usage() {
    echo "Usage: $0 -g <resource-group> -c <cluster-name> -b <bicep-template-path> -p <admin-password> -v <vnet-name> -s <subnet-name> -u <subscription-id>"
    exit 1
}

# Parse command-line arguments
while getopts "g:c:b:p:v:s:u:" opt; do
    case "$opt" in
        g) RESOURCE_GROUP="$OPTARG" ;;
        c) CLUSTER_NAME="$OPTARG" ;;
        b) BICEP_TEMPLATE_PATH="$OPTARG" ;;
        p) ADMIN_PASSWORD="$OPTARG" ;;
        v) VNET_NAME="$OPTARG" ;;
        s) SUBNET_NAME="$OPTARG" ;;
        u) SUBSCRIPTION_ID="$OPTARG" ;;
        *) usage ;;
    esac
done

# Check if all required parameters are provided
missing_params=()

if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    missing_params+=("-g <resource-group>")
fi
if [[ -z "${CLUSTER_NAME:-}" ]]; then
    missing_params+=("-c <cluster-name>")
fi
if [[ -z "${BICEP_TEMPLATE_PATH:-}" ]]; then
    missing_params+=("-b <bicep-template-path>")
fi
if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
    missing_params+=("-p <admin-password>")
fi
if [[ -z "${VNET_NAME:-}" ]]; then
    missing_params+=("-v <vnet-name>")
fi
if [[ -z "${SUBNET_NAME:-}" ]]; then
    missing_params+=("-s <subnet-name>")
fi
if [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
    missing_params+=("-u <subscription-id>")
fi

if [[ ${#missing_params[@]} -gt 0 ]]; then
    echo "Error: Missing required parameters:"
    for param in "${missing_params[@]}"; do
        echo "  $param"
    done
    usage
fi

# Retrieve the Object ID of the managed identity
echo "Retrieving Object ID of the managed identity..."
OID=$(az identity show --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/helm-script-msi" --query principalId -o tsv)
echo "OID: $OID"

# Authenticate with the AKS cluster
echo "Authenticating with AKS cluster..."
export KUBECONFIG=$(pwd)/kubeconfig.yaml
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing  -a || exit 1
echo "Successfully authenticated with AKS cluster."


# # Apply the Kubernetes role using the managed identity
# echo "Applying Kubernetes role for the managed identity..."
# sed "s|__OBJECT_ID__|$OID|g" bootstrap-role.yaml


# # Define VMSS names
# VMSS_NAMES=("dncpool1" "linuxpool1")

# # Loop through VMSS names and create VMSS
# for VMSS_NAME in "${VMSS_NAMES[@]}"; do
#     EXTENSION_NAME="NodeJoin-${VMSS_NAME}"  # Unique extension name for each VMSS
#     echo "Creating VMSS: $VMSS_NAME with extension: $EXTENSION_NAME"

#     az deployment group create \
#         --name "vmss-deployment-${VMSS_NAME}" \
#         --resource-group "$RESOURCE_GROUP" \
#         --template-file "$BICEP_TEMPLATE_PATH" \
#         --parameters vnetname="$VNET_NAME" \
#                      subnetname="$SUBNET_NAME" \
#                      name="$VMSS_NAME" \
#                      adminPassword="$ADMIN_PASSWORD" \
#                      vnetrgname="$RESOURCE_GROUP" \
#                      extensionName="$EXTENSION_NAME" > "./lin-script-${VMSS_NAME}.log" 2>&1 &
# done

# # Wait for all background processes to complete
# wait

# # Display logs for each VMSS deployment
# for VMSS_NAME in "${VMSS_NAMES[@]}"; do
#     echo "Displaying logs for $VMSS_NAME deployment:"
#     cat "./lin-script-${VMSS_NAME}.log"
# done

# # Verify the nodes are ready
# echo "Verifying that nodes are ready..."
# NODES=$(kubectl get nodes -l kubernetes.azure.com/managed=false -o jsonpath='{.items[*].metadata.name}')
# for NODE in $NODES; do
#     READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
#     if [ "$READY" != "True" ]; then
#         echo "Node $NODE is not ready. Exiting."
#         exit 1
#     fi
# done

# echo "All nodes are ready and joined to the AKS cluster."

# # Promote one of the VMSS (e.g., linone) to be a system pool
# SYSTEM_POOL_NAME="dncpool1"
# echo "Promoting VMSS $SYSTEM_POOL_NAME to be a system pool..."
# az aks nodepool update \
#     --cluster-name "$CLUSTER_NAME" \
#     --resource-group "$RESOURCE_GROUP" \
#     --name "$SYSTEM_POOL_NAME" \
#     --mode System

# echo "VMSS $SYSTEM_POOL_NAME has been promoted to a system pool."

# NODE_POOLS_TO_DELETE=("dncpool0" "linuxpool0")  # List of node pools to delete
# # Function to delete a node pool
# delete_node_pool() {
#     local node_pool_name=$1
#     echo "Deleting node pool: $node_pool_name from AKS cluster: $AKS_CLUSTER_NAME in resource group: $RESOURCE_GROUP..."
    
#     # Delete the node pool
#     az aks nodepool delete \
#         --resource-group "$RESOURCE_GROUP" \
#         --cluster-name "$CLUSTER_NAME" \
#         --name "$node_pool_name" \
#         --yes

#     echo "Node pool $node_pool_name deleted successfully."
# }

# # Loop through the node pools and delete them
# for NODE_POOL in "${NODE_POOLS_TO_DELETE[@]}"; do
#     delete_node_pool "$NODE_POOL"
# done

# # Verify the remaining node pools
# echo "Remaining node pools in the cluster:"
# az aks nodepool list --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o table