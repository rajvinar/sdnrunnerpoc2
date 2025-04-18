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
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing  --admin || exit 1
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

# sed "s|__OBJECT_ID__|$OID|g" ./bootstrap-role.yaml | kubectl apply -f -
#         echo "installing azure cni and cns."
#         helm install -n kube-system base9 ./chart --set installCniPlugins.enabled=true --set cilium.enabled=false --set azurecnsUnmanaged.enabled=true --set wiImageCredProvider.enabled=false --set azurecnsUnmanaged.version=v1.6.23 --set azurecnsUnmanaged.versionWindows=v1.6.23


# # Define VMSS names
# VMSS_NAMES=("dncpool12" "linuxpool12")

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
#                      vmsssku="Standard_E8s_v3" \
#                      location="westus" \
#                      extensionName="$EXTENSION_NAME" > "./lin-script-${VMSS_NAME}.log" 2>&1 &
#     wait
# done


# WORKER_VMSS=("linuxpool121")
# # Loop through VMSS names and create VMSS
# for VMSS_NAME in "${WORKER_VMSS[@]}"; do
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
#                      vmsssku="Standard_E8s_v3" \
#                      location="westus" \
#                      extensionName="$EXTENSION_NAME" > "./lin-script-${VMSS_NAME}.log" 2>&1 &
#     wait
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

# Promote one of the VMSS to be a user pool
kubectl label node linuxpool12000000 kubernetes.azure.com/mode=user --overwrite
kubectl label node linuxpool121000000 kubernetes.azure.com/mode=user --overwrite


# install cns and cni
echo "Installing Azure CNS and CNI plugins..."

# Label the nodes to specify the type
kubectl label node linuxpool12000000 node-type=cnscni

# Label the nodes to specify the type
kubectl label node linuxpool12000000 node-type=cnscni
kubectl label node dncpool12000000 node-type=dnc
kubectl label node linuxpool121000000 node-type=cnscni

echo "Deploying azure_cns_configmap.yaml to namespace default..."
kubectl apply -f azure_cns_configmap.yaml -n default

# Deploy the DaemonSet
echo "Deploying azure_cns_daemonset.yaml to namespace default..."
kubectl apply -f azure_cns_daemonset.yaml -n default

echo "Deploying dnc_configmap.yaml to namespace default..."
kubectl apply -f dnc_configmap.yaml -n default

# echo "Deploying dnc_deployment.yaml to namespace default..."
# # TODO: deploy DNC needs to assign MI that can access DB to the dnc node
# kubectl apply -f dnc_deployment.yaml -n default

# # Label the nodes to specify the cx
# kubectl label node linuxpool12000000 cx=vm1
# kubectl label node linuxpool121000000 cx=vm2

# echo "Deploying container1.yaml to node cx=vm1..."
# kubectl apply -f container1.yaml -n default

# echo "Deploying container2.yaml to node cx=vm2..."
# kubectl apply -f container2.yaml -n default

#########################################################################
########################### Label data plane nodes ###########################
# # Variables
# NODE_LABEL_KEY="dncnode"  # Key for the label

# # Function to label a node
# label_node() {
#   local node_name=$1
#   local label_key=$2
#   local label_value=$3

#   echo "Labeling node: $node_name with label: $label_key=$label_value"
#   kubectl label node "$node_name" "$label_key=$label_value" --overwrite
#   echo "Successfully labeled node: $node_name with label: $label_key=$label_value"
# }

# # Get the list of nodes to label
# # Replace this with your logic to fetch node names dynamically
# NODE_NAMES=("linuxpool12000000" "linuxpool121000000")

# # Label each node
# for NODE_NAME in $NODE_NAMES; do
#   label_node "$NODE_NAME" "$NODE_LABEL_KEY" "$NODE_NAME"
# done

# echo "All nodes have been successfully labeled."

######################## Port Forwarding to DNC ########################
# NAMESPACE="default"
# LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
# LOCAL_PORT=9000  # Local port to forward
# REMOTE_PORT=9000  # Pod's port to forward
# DNC_POD="dnc-7b76546bfd-kcc4d"

# # Start port forwarding
# echo "Starting port forwarding from localhost:$LOCAL_PORT to $DNC_POD:$REMOTE_PORT..."
# kubectl port-forward -n "$NAMESPACE" pod/"$DNC_POD" "$LOCAL_PORT:$REMOTE_PORT" & PORT_FORWARD_PID=$!

# # Wait for port forwarding to establish
# sleep 20

# # Check if the port forwarding process is running
# if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
#   echo "Error: Port forwarding failed to start"
#   exit 1
# fi

# # Log the forwarded URL
# DNC_URL="http://localhost:$LOCAL_PORT"
# echo "Successfully port forwarded to DNC: $DNC_URL"


# ############################ Register node with DNC  ############################
# # Variables
# DNC_ENDPOINT=$DNC_URL #"https://10.224.0.65:9000"  # Replace with the actual DNC endpoint
# NODE_ID="dncpool12000000"                 # Replace with the actual Node ID
# NODE_API="$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01"
# JSON_CONTENT_TYPE="application/json"

# # Node information payload
# NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": "10.224.0.69",
#   "OrchestratorType": "Kubernetes",
#   "InfrastructureNetwork": "cd28d33f-1589-44d3-98a4-7cc84d03d6d4",
#   "AZID": "",
#   "NodeType": "",
#   "NodeSet": "",
#   "NumCores": "0",
#   "DualstackEnabled": "false"
# }
# EOF
# )

# # Send HTTP POST request to add the node
# response=$(curl -s -w "%{http_code}" -o /tmp/add_node_response.json -X POST "$NODE_API" \
#   -H "Content-Type: $JSON_CONTENT_TYPE" \
#   -d "$NODE_INFO_JSON")

# # Extract HTTP status code
# http_status=$(tail -n1 <<< "$response")

# # Check if the request was successful
# if [[ "$http_status" -ne 200 ]]; then
#   echo "Failed to add node. HTTP status: $http_status"
#   cat /tmp/add_node_response.json
#   exit 1
# fi

# echo "Node added successfully!"
# cat /tmp/add_node_response.json

############################ Join Vnet ############################
# NETWORK_ID="10177921-2ed7-464c-be21-661407a1e10f"
# DNC_ENDPOINT=$DNC_URL
# RETRY_COUNT=20  # Number of retry attempts
# RETRY_DELAY=3  # Delay between retries in seconds

# add_vnet() {
#   #DNC_ENDPOINT=$DNC_URL #"https://10.224.0.65:9000"  # Replace with the actual DNC endpoint
#   #NETWORK_ID="10177921-2ed7-464c-be21-661407a1e10f"  # Replace with your network ID
#   NETWORK_TYPE="AzureNet" 

#   network_request=$(cat <<EOF
# {
#   "NetworkType": "$NETWORK_TYPE"
# }
# EOF
# )

#   echo "Adding network with ID: $NETWORK_ID"

#   # Send the POST request to the DNC API
#   response=$(curl -s -w "%{http_code}" -o /tmp/add_network_response.json -X POST "$DNC_ENDPOINT/networks/$NETWORK_ID?api-version=2018-03-01" \
#     -H "Content-Type: application/json" \
#     -d "$network_request")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to add network $NETWORK_ID. HTTP status: $http_status"
#     cat /tmp/add_network_response.json
#     exit 1
#   fi

#   echo "Successfully added network $NETWORK_ID."
#   cat /tmp/add_network_response.json
# }

# check_vnet_status() {
#   echo "Checking status of VNet: $NETWORK_ID"

#   # Send the GET request to check the VNet status
#   response=$(curl -s -w "%{http_code}" -o /tmp/vnet_status_response.json -X GET "$DNC_ENDPOINT/networks/$NETWORK_ID/status?api-version=2018-03-01" \
#     -H "Content-Type: application/json")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to get status for VNet $NETWORK_ID. HTTP status: $http_status"
#     cat /tmp/vnet_status_response.json
#     return 1
#   fi

#   # Parse the status from the response
#   vnet_status=$(jq -r '.Status' /tmp/vnet_status_response.json)
#   if [[ "$vnet_status" != "Completed" ]]; then
#     echo "VNet $NETWORK_ID is not in 'Completed' status. Current status: $vnet_status"
#     return 1
#   fi

#   echo "VNet $NETWORK_ID is in 'Completed' status."
# }

# # Retry logic for adding the VNet
# attempt=1
# while [[ $attempt -le $RETRY_COUNT ]]; do
#   if add_vnet; then
#     echo "Add VNet succeeded on attempt $attempt."
#     break
#   fi

#   echo "Add VNet failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
#   sleep $RETRY_DELAY
#   attempt=$((attempt + 1))
# done

# if [[ $attempt -gt $RETRY_COUNT ]]; then
#   echo "Failed to add VNet after $RETRY_COUNT attempts."
#   exit 1
# fi

# # Retry logic for checking the VNet status
# attempt=1
# while [[ $attempt -le $RETRY_COUNT ]]; do
#   if check_vnet_status; then
#     echo "VNet status check succeeded on attempt $attempt."
#     exit 0
#   fi

#   echo "VNet status check failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
#   sleep $RETRY_DELAY
#   attempt=$((attempt + 1))
# done

# echo "Failed to verify VNet status after $RETRY_COUNT attempts."
# exit 1

############################ Stop port forwarding ############################
# # Stop port forwarding
# echo "Stopping port forwarding..."
# kill $PORT_FORWARD_PID

# sleep 20

# # Verify the process has stopped
# if kill -0 $PORT_FORWARD_PID 2>/dev/null; then
#   echo "Error: Failed to stop port forwarding"
#   exit 1
# fi

# echo "Port forwarding stopped successfully."




# Variables
END_TIME=$((SECONDS + 600))  # 30 minutes = 1800 seconds
INTERVAL=10  # Interval between iterations in seconds

echo "Starting the loop for 30 minutes..."

# Loop for 30 minutes
while [ $SECONDS -lt $END_TIME ]; do
  echo "Running task at $(date)..."

  # Wait for the specified interval before the next iteration
  sleep $INTERVAL
done

echo "Loop completed after 30 minutes."