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
while getopts "g:c:b:p:v:s:u:t:V:m:d:" opt; do
    case "$opt" in
        g) RESOURCE_GROUP="$OPTARG" ;;
        c) CLUSTER_NAME="$OPTARG" ;;
        b) BICEP_TEMPLATE_PATH="$OPTARG" ;;
        p) ADMIN_PASSWORD="$OPTARG" ;;
        v) INFRA_VNET_NAME="$OPTARG" ;;
        s) INFRA_SUBNET_NAME="$OPTARG" ;;
        u) SUBSCRIPTION_ID="$OPTARG" ;;
        t) SAL_TOKENS="$OPTARG" ;;
        # w) WORKER_NODES_INPUT="$OPTARG" ;;
        # d) DNC_NODES_INPUT="$OPTARG" ;;
        # W) WORKER_VMSSES_INPUT="$OPTARG" ;;
        # D) DNC_VMSSES_INPUT="$OPTARG" ;;
        V) CUSTOMER_VNET_ID="$OPTARG" ;;
        # S) CUSTOMER_SUBNET_NAMES_INPUT="$OPTARG" ;; 
        # P) PODS_INPUT="$OPTARG" ;;
        # N) DNC_POD_NAME="$OPTARG" ;;
        # n) NC_NODES_INPUT="$OPTARG" ;;
        # o) NODES_INPUT="$OPTARG" ;;
        m) AKS_KUBERNETES_SERVICE_MANAGED_IDENTITY_CLIENT_ID="$OPTARG" ;; 
        d) DB_NAME="$OPTARG" ;; 
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
if [[ -z "${INFRA_VNET_NAME:-}" ]]; then
    missing_params+=("-v <infra-vnet-name>")
fi
if [[ -z "${INFRA_SUBNET_NAME:-}" ]]; then
    missing_params+=("-s <infra-subnet-name>")
fi
if [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
    missing_params+=("-u <subscription-id>")
fi
if [[ -z "${SAL_TOKENS:-}" ]]; then
    missing_params+=("-t <sal-token>")
fi
if [[ -z "${DB_NAME:-}" ]]; then
    missing_params+=("-d <db-name>")
fi
# if [[ -z "${WORKER_NODES_INPUT:-}" ]]; then
#     missing_params+=("-w <worker-nodes>")
# fi
# if [[ -z "${DNC_NODES_INPUT:-}" ]]; then
#     missing_params+=("-d <dnc-nodes>")
# fi
# if [[ -z "${WORKER_VMSSES_INPUT:-}" ]]; then
#     missing_params+=("-W <worker-vmsses>")
# fi
# if [[ -z "${DNC_VMSSES_INPUT:-}" ]]; then
#     missing_params+=("-D <dnc-vmsses>")
# fi
if [[ -z "${CUSTOMER_VNET_ID:-}" ]]; then
    missing_params+=("-V <customer-vnet-id>")
fi
# if [[ -z "${CUSTOMER_SUBNET_NAMES_INPUT:-}" ]]; then
#     missing_params+=("-S <customer-subnet-names>")
# fi
# if [[ -z "${PODS_INPUT:-}" ]]; then
#     missing_params+=("-P <pods>")
# fi
# if [[ -z "${DNC_POD_NAME:-}" ]]; then
#     missing_params+=("-N <dnc-pod-name>")
# fi
# if [[ -z "${NC_NODES_INPUT:-}" ]]; then
#     missing_params+=("-n <nc-nodes>")
# fi
# if [[ -z "${NODES_INPUT:-}" ]]; then
#     missing_params+=("-n <nodes>")
# fi
if [[ -z "${AKS_KUBERNETES_SERVICE_MANAGED_IDENTITY_CLIENT_ID:-}" ]]; then
    missing_params+=("-m <managed-identity-client-id>")
fi

if [[ ${#missing_params[@]} -gt 0 ]]; then
    echo "Error: Missing required parameters:"
    for param in "${missing_params[@]}"; do
        echo "  $param"
    done
    usage
fi

# Convert comma-separated inputs into arrays
# IFS=',' read -r -a WORKER_NODES <<< "$WORKER_NODES_INPUT"
# IFS=',' read -r -a DNC_NODES <<< "$DNC_NODES_INPUT"
# IFS=',' read -r -a WORKER_VMSSES <<< "$WORKER_VMSSES_INPUT"
# IFS=',' read -r -a DNC_VMSSES <<< "$DNC_VMSSES_INPUT"
# IFS=',' read -r -a PODS <<< "$PODS_INPUT"
# IFS=',' read -r -a NC_NODES <<< "$NC_NODES_INPUT"
# IFS=',' read -r -a NODES <<< "$NODES_INPUT"  # Convert nodes input into an array
# IFS=',' read -r -a CUSTOMER_SUBNET_NAMES <<< "$CUSTOMER_SUBNET_NAMES_INPUT"

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