#!/bin/bash

set -euxo pipefail

# Usage function to display help
usage() {
    echo "Usage: $0 -g <resource-group> \
-c <cluster-name> \
-b <bicep-template-path> \
-p <admin-password> \
-v <infra-vnet-name> \
-s <infra-subnet-name> \
-u <subscription-id> \
-t <sal-token> \
-V <customer-vnet-id>     : ID of the customer virtual network \
-m <managed-identity-client-id> : Managed Identity Client ID for AKS
-d <db-name>"
    exit 1
}

# Parse command-line arguments
while getopts "g:c:u:" opt; do
    case "$opt" in
        g) RESOURCE_GROUP="$OPTARG" ;;
        c) CLUSTER_NAME="$OPTARG" ;;
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
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing  --admin || exit 1
echo "Successfully authenticated with AKS cluster."


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

apk add --no-cache jq
apk add --no-cache util-linux
apk add --no-cache jq
apk add --no-cache gettext


# Retrieve the Object ID of the managed identity
echo "Retrieving Object ID of the managed identity..."
OID=$(az identity show --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/helm-script-msi3" --query principalId -o tsv)
echo "OID: $OID"

sed "s|__OBJECT_ID__|$OID|g" ./bootstrap-role.yaml | kubectl apply -f -
        echo "installing azure cni and cns."
        helm install -n kube-system $(uuidgen) ./chart --set installCniPlugins.enabled=true --set cilium.enabled=false --set azurecnsUnmanaged.enabled=true --set wiImageCredProvider.enabled=false --set azurecnsUnmanaged.version=v1.6.23 --set azurecnsUnmanaged.versionWindows=v1.6.23