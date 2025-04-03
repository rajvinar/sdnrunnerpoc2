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

az account set -s $SUBSCRIPTION_ID

# Authenticate with the AKS cluster
echo "Authenticating with AKS cluster..."
export KUBECONFIG=$(pwd)/kubeconfig.yaml
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing  -a || exit 1
echo "Successfully authenticated with AKS cluster."

# Retrieve the Object ID of the managed identity
echo "Retrieving Object ID of the managed identity..."
OID=$(az identity show --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/helm-script-msi3" --query principalId -o tsv)
echo "OID: $OID"

pwd  # Prints the current working directory
find . -type d  # Lists all directories (including subdirectories)
ls

if [ ! -d "./chart" ]; then
    mkdir -p chart
    mkdir -p chart/templates

    mv values.yaml chart/
    mv Chart.yaml chart/
    mv cni-plugins-installer.yaml chart/templates/
    mv cns-unmanaged-windows.yaml chart/templates/
    mv cns-unmanaged.yaml chart/templates/
else
    echo "Folder 'chart' already exists."
fi

ls

apk add --no-cache curl

if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found! Installing..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    wait
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    kubectl version --client
fi


if ! command -v helm &> /dev/null; then
    echo "helm not found! Installing..."
    apk add --no-cache helm
    wait
    helm version
fi

sed "s|__OBJECT_ID__|$OID|g" ./bootstrap-role.yaml | kubectl apply -f -
        echo "installing azure cni and cns."
        helm install -n kube-system base8 ./chart --set installCniPlugins.enabled=true --set cilium.enabled=false --set azurecnsUnmanaged.enabled=true --set wiImageCredProvider.enabled=false --set azurecnsUnmanaged.version=v1.6.23 --set azurecnsUnmanaged.versionWindows=v1.6.23
        # helm install -n kube-system base4 ./chart --set cilium.enabled=false --set azurecnsUnmanaged.enabled=true --set wiImageCredProvider.enabled=false --set azurecnsUnmanaged.version=v1.6.23 --set azurecnsUnmanaged.versionWindows=v1.6.23


# Define VMSS names
VMSS_NAMES=("dncpool12" "linuxpool12")

# Loop through VMSS names and create VMSS
for VMSS_NAME in "${VMSS_NAMES[@]}"; do
    EXTENSION_NAME="NodeJoin-${VMSS_NAME}"  # Unique extension name for each VMSS
    echo "Creating VMSS: $VMSS_NAME with extension: $EXTENSION_NAME"

    az deployment group create \
        --name "vmss-deployment-${VMSS_NAME}" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$BICEP_TEMPLATE_PATH" \
        --parameters vnetname="$VNET_NAME" \
                     subnetname="$SUBNET_NAME" \
                     name="$VMSS_NAME" \
                     adminPassword="$ADMIN_PASSWORD" \
                     vnetrgname="$RESOURCE_GROUP" \
                     vmsssku="Standard_E8s_v3" \
                     location="eastus2" \
                     extensionName="$EXTENSION_NAME" > "./lin-script-${VMSS_NAME}.log" 2>&1 &
    wait
done

# Wait for all background processes to complete
wait

# Display logs for each VMSS deployment
for VMSS_NAME in "${VMSS_NAMES[@]}"; do
    echo "Displaying logs for $VMSS_NAME deployment:"
    cat "./lin-script-${VMSS_NAME}.log"
done

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

# Verify the remaining node pools
echo "Remaining node pools in the cluster:"
az aks nodepool list --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o table