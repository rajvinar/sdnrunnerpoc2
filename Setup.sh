#!/bin/bash

set -euxo pipefail

# Usage function to display help
usage() {
    echo "Usage: $0 -g <resource-group> -c <cluster-name> -u <subscription-id> -w <worker-nodes> -d <dnc-nodes> -W <worker-vmsses> -D <dnc-vmsses> -V <customer-vnet-id> -S <customer-subnet-name> -P <pods> -N <dnc-pod-name> ..."
    echo ""
    echo "Required Parameters:"
    echo "  -g <resource-group>       : Name of the Azure resource group"
    echo "  -c <cluster-name>         : Name of the AKS cluster"
    echo "  -u <subscription-id>      : Azure subscription ID"
    echo "  -w <worker-nodes>         : Comma-separated list of worker node names"
    echo "  -d <dnc-nodes>            : Comma-separated list of DNC node names"
    echo "  -W <worker-vmsses>        : Comma-separated list of worker VMSS names"
    echo "  -D <dnc-vmsses>           : Comma-separated list of DNC VMSS names"
    echo "  -V <customer-vnet-id>     : ID of the customer virtual network"
    echo "  -S <customer-subnet-names> : Comma-separated list of customer subnet names"
    echo "  -P <pods>                 : Comma-separated list of pod details in the format 'pod-name|node-name|yaml-file|label-selector'"
    echo "  -N <dnc-pod-name>         : Name of the DNC pod for port forwarding"
    echo "  -n <nc-nodes>             : Comma-separated list of node details in the format 'node-name|node-ip|pod-name'"
    echo "  -o <nodes>                : Comma-separated list of node details in the format 'node-name|node-ip'"
    echo "  -m <managed-identity-client-id> : Managed Identity Client ID for AKS"
    exit 1
}

# Parse command-line arguments
while getopts "g:c:b:p:v:s:u:w:d:W:D:V:S:P:N:n:o:m:" opt; do
    case "$opt" in
        g) RESOURCE_GROUP="$OPTARG" ;;
        c) CLUSTER_NAME="$OPTARG" ;;
        u) SUBSCRIPTION_ID="$OPTARG" ;;
        w) WORKER_NODES_INPUT="$OPTARG" ;;
        d) DNC_NODES_INPUT="$OPTARG" ;;
        W) WORKER_VMSSES_INPUT="$OPTARG" ;;
        D) DNC_VMSSES_INPUT="$OPTARG" ;;
        V) CUSTOMER_VNET_ID="$OPTARG" ;;
        S) CUSTOMER_SUBNET_NAMES_INPUT="$OPTARG" ;; 
        P) PODS_INPUT="$OPTARG" ;;
        N) DNC_POD_NAME="$OPTARG" ;;
        n) NC_NODES_INPUT="$OPTARG" ;;
        o) NODES_INPUT="$OPTARG" ;;
        m) AKS_KUBERNETES_SERVICE_MANAGED_IDENTITY_CLIENT_ID="$OPTARG" ;; 
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
fi
if [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
    missing_params+=("-u <subscription-id>")
fi
if [[ -z "${WORKER_NODES_INPUT:-}" ]]; then
    missing_params+=("-w <worker-nodes>")
fi
if [[ -z "${DNC_NODES_INPUT:-}" ]]; then
    missing_params+=("-d <dnc-nodes>")
fi
if [[ -z "${WORKER_VMSSES_INPUT:-}" ]]; then
    missing_params+=("-W <worker-vmsses>")
fi
if [[ -z "${DNC_VMSSES_INPUT:-}" ]]; then
    missing_params+=("-D <dnc-vmsses>")
fi
if [[ -z "${CUSTOMER_VNET_ID:-}" ]]; then
    missing_params+=("-V <customer-vnet-id>")
fi
if [[ -z "${CUSTOMER_SUBNET_NAMES_INPUT:-}" ]]; then
    missing_params+=("-S <customer-subnet-names>")
fi
if [[ -z "${PODS_INPUT:-}" ]]; then
    missing_params+=("-P <pods>")
fi
if [[ -z "${DNC_POD_NAME:-}" ]]; then
    missing_params+=("-N <dnc-pod-name>")
fi
if [[ -z "${NC_NODES_INPUT:-}" ]]; then
    missing_params+=("-n <nc-nodes>")
fi
if [[ -z "${NODES_INPUT:-}" ]]; then
    missing_params+=("-n <nodes>")
fi
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
IFS=',' read -r -a WORKER_NODES <<< "$WORKER_NODES_INPUT"
IFS=',' read -r -a DNC_NODES <<< "$DNC_NODES_INPUT"
IFS=',' read -r -a WORKER_VMSSES <<< "$WORKER_VMSSES_INPUT"
IFS=',' read -r -a DNC_VMSSES <<< "$DNC_VMSSES_INPUT"
IFS=',' read -r -a PODS <<< "$PODS_INPUT"
IFS=',' read -r -a NC_NODES <<< "$NC_NODES_INPUT"
IFS=',' read -r -a NODES <<< "$NODES_INPUT"  # Convert nodes input into an array
IFS=',' read -r -a CUSTOMER_SUBNET_NAMES <<< "$CUSTOMER_SUBNET_NAMES_INPUT"


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

apk add --no-cache util-linux
apk add --no-cache jq
apk add --no-cache gettext


# Label the worker nodes and deploy the cns ConfigMap and DaemonSet
echo "Labeling worker nodes..."
WORKER_NODES=("linuxpool163000000") # TODO : make it come from inputs
# Label key and value
LABEL_KEY="kubernetes.azure.com/mode"
LABEL_VALUE="user"
# Loop through each node and apply the label
for NODE in "${WORKER_NODES[@]}"; do
  kubectl label node "$NODE" "$LABEL_KEY=$LABEL_VALUE" --overwrite
  kubectl label node "$NODE" node-type=cnscni --overwrite
  echo "Successfully labeled node: $NODE"
done

WORKER_VMSSES=("linuxpool163") # TODO : make it come from inputs
# Assign MI to worker nodes to access runner worker image
echo "Assigning Managed Identity to worker nodes..."
for VMSS in "${WORKER_VMSSES[@]}"; do
    az vmss identity assign --name $VMSS --resource-group $RESOURCE_GROUP --identities $AKS_KUBERNETES_SERVICE_MANAGED_IDENTITY_CLIENT_ID
    wait
done

# echo "Deploying cns ConfigMap and DaemonSet..."
# Deploy the cns ConfigMap
echo "Deploying azure_cns_configmap.yaml to namespace default..."
kubectl apply -f azure_cns_configmap.yaml -n default

# Deploy the cns DaemonSet
echo "Deploying azure_cns_daemonset.yaml to namespace default..."
kubectl apply -f azure_cns_daemonset.yaml -n default

# Label the dnc nodes and deploy the dnc ConfigMap and Deployment
DNC_NODES=("dncpool15000000") # TODO : make it come from inputs
echo "Labeling dnc node..."
kubectl label node ${DNC_NODES[0]} node-type=dnc

echo "Deploying dnc_configmap.yaml to namespace default..."
kubectl apply -f dnc_configmap.yaml -n default

# Assign MI to worker nodes to access dnc image
DNC_VMSSES=("linuxpool163") # TODO : make it come from inputs
echo "Assigning Managed Identity to dnc node..."
for VMSS in "${DNC_VMSSES[@]}"; do
    az vmss identity assign --name $VMSS --resource-group $RESOURCE_GROUP --identities $AKS_KUBERNETES_SERVICE_MANAGED_IDENTITY_CLIENT_ID
    wait
done

echo "Deploying dnc_deployment.yaml to namespace default..."
kubectl apply -f dnc_deployment.yaml -n default


########### Port Forwarding Setup ###########
DNC_POD=$DNC_POD_NAME
NAMESPACE="default"  # Replace with the namespace of the DNC deployment
LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
LOCAL_PORT=9000  # Local port to forward
REMOTE_PORT=9000  # Pod's port to forward

DNC_POD="dnc-7f75b67795-cpc5b" # TODO: make it come from inputs

# Start port forwarding
echo "Starting port forwarding from localhost:$LOCAL_PORT to $DNC_POD:$REMOTE_PORT..."
kubectl port-forward -n "$NAMESPACE" pod/"$DNC_POD" "$LOCAL_PORT:$REMOTE_PORT" & PORT_FORWARD_PID=$!

# Wait for port forwarding to establish
sleep 20

# Check if the port forwarding process is running
if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
  echo "Error: Port forwarding failed to start"
  exit 1
fi

# Log the forwarded URL
DNC_URL="http://localhost:$LOCAL_PORT"
echo "Successfully port forwarded to DNC: $DNC_URL"

########### Port Forwarding Setup End ###########

################ Join vnet ################
NETWORK_ID=$CUSTOMER_VNET_ID
DNC_ENDPOINT=$DNC_URL
RETRY_COUNT=100  # Number of retry attempts
RETRY_DELAY=3  # Delay between retries in seconds

NETWORK_ID="3f84330f-6410-4996-bb28-78513d2eb093" # This is customer vnet id. TODO: Make it come from inputs 

add_vnet() {
  NETWORK_TYPE="AzureNet" 

  network_request=$(cat <<EOF
{
  "NetworkType": "$NETWORK_TYPE"
}
EOF
)

  echo "Adding network with ID: $NETWORK_ID"

  # Send the POST request to the DNC API
  response=$(curl -s -w "%{http_code}" -o /tmp/add_network_response.json -X POST "$DNC_ENDPOINT/networks/$NETWORK_ID?api-version=2018-03-01" \
    -H "Content-Type: application/json" \
    -d "$network_request")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to add network $NETWORK_ID. HTTP status: $http_status"
    cat /tmp/add_network_response.json
    exit 1
  fi

  echo "Successfully added network $NETWORK_ID."
  cat /tmp/add_network_response.json
}

check_vnet_status() {
  echo "Checking status of VNet: $NETWORK_ID"

  # Send the GET request to check the VNet status
  response=$(curl -s -w "%{http_code}" -o /tmp/vnet_status_response.json -X GET "$DNC_ENDPOINT/networks/$NETWORK_ID/status?api-version=2018-03-01" \
    -H "Content-Type: application/json")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to get status for VNet $NETWORK_ID. HTTP status: $http_status"
    cat /tmp/vnet_status_response.json
    return 1
  fi

  # Parse the status from the response
  vnet_status=$(jq -r '.Status' /tmp/vnet_status_response.json)
  if [[ "$vnet_status" != "Completed" ]]; then
    echo "VNet $NETWORK_ID is not in 'Completed' status. Current status: $vnet_status"
    return 1
  fi

  echo "VNet $NETWORK_ID is in 'Completed' status."
}

# Retry logic for adding the VNet
attempt=1
while [[ $attempt -le $RETRY_COUNT ]]; do
  if add_vnet; then
    echo "Add VNet succeeded on attempt $attempt."
    break
  fi

  echo "Add VNet failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
  sleep $RETRY_DELAY
  attempt=$((attempt + 1))
done

if [[ $attempt -gt $RETRY_COUNT ]]; then
  echo "Failed to add VNet after $RETRY_COUNT attempts."
  exit 1
fi

# Retry logic for checking the VNet status
attempt=1
while [[ $attempt -le $RETRY_COUNT ]]; do
  if check_vnet_status; then
    echo "VNet status check succeeded on attempt $attempt."
    exit 0
  fi

  echo "VNet status check failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
  sleep $RETRY_DELAY
  attempt=$((attempt + 1))
done

echo "Failed to verify VNet status after $RETRY_COUNT attempts."
exit 1

############# Join subnet to DNC #############
# Variables
DNC_API_ENDPOINT=$DNC_URL
CUSTOMER_VNET_GUID=$CUSTOMER_VNET_ID
API_VERSION="2018-03-01"  # Replace with the API version
RETRY_COUNT=20  # Number of retry attempts
RETRY_DELAY=3  # Delay between retries in seconds

CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # # This is customer vnet id. TODO: Make it come from inputs 
CUSTOMER_SUBNET_NAMES=("delegatedSubnet" "delegatedSubnet1")  # TODO: Make it come from inputs 

# Function to add a subnet
add_subnet() {
  local CUSTOMER_SUBNET_NAME=$1
  echo "Attempting to add subnet: $CUSTOMER_SUBNET_NAME to VNet: $CUSTOMER_VNET_GUID"
  echo "AUTH_TOKEN: $AUTH_TOKEN"
  # Construct the subnet request payload
  subnet_request=$(cat <<EOF
{
  "NetworkID": "$CUSTOMER_VNET_GUID",
  "SubnetName": "$CUSTOMER_SUBNET_NAME",
  "AuthenticationToken": "$AUTH_TOKEN"
}
EOF
)

  # Send the POST request to add the subnet
  response=$(curl -s -w "%{http_code}" -o /tmp/add_subnet_response.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/subnets/$CUSTOMER_SUBNET_NAME?api-version=$API_VERSION" \
    -H "Content-Type: application/json" \
    -d "$subnet_request")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to add subnet $CUSTOMER_SUBNET_NAME. HTTP status: $http_status"
    cat /tmp/add_subnet_response.json
    return 1
  fi

  echo "Successfully added subnet: $CUSTOMER_SUBNET_NAME"
  cat /tmp/add_subnet_response.json
}

# Function to check the subnet status
check_subnet_status() {
  local CUSTOMER_SUBNET_NAME=$1
  echo "Checking status of subnet: $CUSTOMER_SUBNET_NAME in VNet: $CUSTOMER_VNET_GUID"

  # Send the GET request to check the subnet status
  response=$(curl -s -w "%{http_code}" -o /tmp/subnet_status_response.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/subnets/$CUSTOMER_SUBNET_NAME/status?api-version=$API_VERSION" \
    -H "Content-Type: application/json")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to get status for subnet $CUSTOMER_SUBNET_NAME. HTTP status: $http_status"
    cat /tmp/subnet_status_response.json
    return 1
  fi

  # Parse the status from the response
  subnet_status=$(jq -r '.Status' /tmp/subnet_status_response.json)
  if [[ "$subnet_status" != "Completed" ]]; then
    echo "Subnet $CUSTOMER_SUBNET_NAME is not in 'Completed' status. Current status: $subnet_status"
    return 1
  fi

  echo "Subnet $CUSTOMER_SUBNET_NAME is in 'Completed' status."
}

# Retry logic for adding the subnets
for CUSTOMER_SUBNET_NAME in "${CUSTOMER_SUBNET_NAMES[@]}"; do
  attempt=1
  while [[ $attempt -le $RETRY_COUNT ]]; do
    if add_subnet "$CUSTOMER_SUBNET_NAME"; then
      echo "Add subnet succeeded on attempt $attempt for subnet: $CUSTOMER_SUBNET_NAME."
      break
    fi

    echo "Add subnet failed on attempt $attempt for subnet: $CUSTOMER_SUBNET_NAME. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    attempt=$((attempt + 1))
  done

  if [[ $attempt -gt $RETRY_COUNT ]]; then
    echo "Failed to add subnet: $CUSTOMER_SUBNET_NAME after $RETRY_COUNT attempts."
    exit 1
  fi

  # Retry logic for checking the subnet status
  attempt=1
  while [[ $attempt -le $RETRY_COUNT ]]; do
    if check_subnet_status "$CUSTOMER_SUBNET_NAME"; then
      echo "Subnet status check succeeded on attempt $attempt for subnet: $CUSTOMER_SUBNET_NAME."
      break
    fi

    echo "Subnet status check failed on attempt $attempt for subnet: $CUSTOMER_SUBNET_NAME. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    attempt=$((attempt + 1))
  done

  if [[ $attempt -gt $RETRY_COUNT ]]; then
    echo "Failed to verify subnet status for subnet: $CUSTOMER_SUBNET_NAME after $RETRY_COUNT attempts."
    exit 1
  fi
done

###################### Register nodes in DNC ######################
# Define an array of nodes with their details
NODES=(
  "linuxpool160000000|10.224.0.76"  # Format: NODE_ID|NODE_IP TODO: Make it come from inputs
  "linuxpool161000000|10.224.0.78"
)

DNC_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
JSON_CONTENT_TYPE="application/json"

# Function to register a node
register_node() {
  local NODE_ID=$1
  local NODE_IP=$2

  echo "Registering node: $NODE_ID with IP: $NODE_IP"

  # Node information payload
  NODE_INFO_JSON=$(cat <<EOF
{
  "IPAddresses": ["$NODE_IP"],
  "OrchestratorType": "Kubernetes",
  "InfrastructureNetwork": "52ebbf7f-eb3b-4eea-8ef6-51fe3e2d8bcd",
  "AZID": "",
  "NodeType": "",
  "NodeSet": "",
  "NumCores": 8,
  "DualstackEnabled": false
}
EOF
  )

  # Send HTTP POST request to add the node
  response=$(curl -s -w "%{http_code}" -o /tmp/add_node_response_$NODE_ID.json -X POST "$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01" \
    -H "Content-Type: $JSON_CONTENT_TYPE" \
    -d "$NODE_INFO_JSON")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to add node $NODE_ID. HTTP status: $http_status"
    cat /tmp/add_node_response_$NODE_ID.json
    return 1
  fi

  echo "Node $NODE_ID added successfully!"
  cat /tmp/add_node_response_$NODE_ID.json
}

# Iterate over the nodes and register each one
for node in "${NODES[@]}"; do
  IFS="|" read -r NODE_ID NODE_IP <<< "$node"
  if ! register_node "$NODE_ID" "$NODE_IP"; then
    echo "Error: Failed to register node $NODE_ID"
    exit 1
  fi
done

echo "All nodes registered successfully!"

########################### Create NCs ###########################
CUSTOMER_VNET_GUID=$CUSTOMER_VNET_ID
DNC_API_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
POD_NAMESPACE="default"  # Replace with the pod namespace
RETRY_COUNT=20  # Number of retry attempts
RETRY_DELAY=3  # Delay between retries in seconds
IP_CONSTRAINT=""
NODE_CONSTRAINT=""
SECONDARY_IP_COUNT=0
PRIMARY_IP_PREFIX_BITS=0
CONTAINER_TYPE="AzureContainerInstance"
OWNER_ID=""
RESERVATION_ID=""
RESERVATION_SET_ID=""
HOST_TO_NC=false
NC_TO_HOST=false
nc_id=""

NC_NODES=(
  "linuxpool160000000|10.224.0.76|container1-pod"  # Format: NODE_NAME|NODE_IP|POD_NAME TODO: Make it come from inputs
  "linuxpool161000000|10.224.0.78|container2-pod"
)
CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # TODO: make it come from inputs
CUSTOMER_SUBNET_NAMES=("delegatedSubnet" "delegatedSubnet1")

# Function to create a network container (NC)
create_nc() {
  local NODE_NAME=$1
  local NODE_IP=$2
  local POD_NAME=$3
  local CUSTOMER_SUBNET_NAME=$4
  local NC_ID=$(uuidgen)  # Generate a unique NC ID
  nc_id="$NC_ID"
  echo "Attempting to create NC: $NC_ID on node: $NODE_NAME with pod: $POD_NAME"

  # Construct the NC request payload
  if [[ -z "$RESERVATION_ID" && -z "$RESERVATION_SET_ID" ]]; then
    # V2 request
    nc_request=$(cat <<EOF
{
  "AllocationRequest": {
    "SubnetName": "$CUSTOMER_SUBNET_NAME",
    "IPConstraint": "$IP_CONSTRAINT",
    "NodeConstraint": "$NODE_CONSTRAINT",
    "SecondaryIPCount": $SECONDARY_IP_COUNT,
    "PrimaryIPPrefixBits": $PRIMARY_IP_PREFIX_BITS
  },
  "AssociationInfo": {
    "NodeID": "$NODE_NAME",
    "InterfaceID": "$NODE_IP",
    "ContainerType": "$CONTAINER_TYPE",
    "OrchestratorContext": {
      "PodName": "$POD_NAME",
      "PodNamespace": "$POD_NAMESPACE"
    }
  },
  "AllowHostToNCCommunication": $HOST_TO_NC,
  "AllowNCToHostCommunication": $NC_TO_HOST,
  "OwnerID": "$OWNER_ID"
}
EOF
    )
  else
    # V1 request
    nc_request=$(cat <<EOF
{
  "ReservationID": "$RESERVATION_ID",
  "ReservationSetID": "$RESERVATION_SET_ID",
  "AssociationInfo": {
    "NodeID": "$NODE_NAME",
    "InterfaceID": "$NODE_IP",
    "ContainerType": "$CONTAINER_TYPE",
    "OrchestratorContext": {
      "PodName": "$POD_NAME",
      "PodNamespace": "$POD_NAMESPACE"
    }
  },
  "AllowHostToNCCommunication": $HOST_TO_NC,
  "AllowNCToHostCommunication": $NC_TO_HOST,
  "OwnerID": "$OWNER_ID"
}
EOF
    )
  fi

  echo "NC request payload: $nc_request"

  # Send the POST request to create the NC
  response=$(curl -s -w "%{http_code}" -o /tmp/create_nc_response_$NC_ID.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID?api-version=2018-03-01" \
    -H "Content-Type: application/json" \
    -d "$nc_request")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful or if there was a conflict
  if [[ "$http_status" -ne 200 && "$http_status" -ne 409 ]]; then
    echo "Failed to create NC $NC_ID. HTTP status: $http_status"
    cat /tmp/create_nc_response_$NC_ID.json
    return 1
  fi

  echo "Successfully created NC: $NC_ID"
  cat /tmp/create_nc_response_$NC_ID.json
}

# Function to poll the NC status
poll_nc_status() {
  local NC_ID=$1

  echo "Polling status of NC: $NC_ID"

  # Send the GET request to check the NC status
  response=$(curl -s -w "%{http_code}" -o /tmp/nc_status_response_$NC_ID.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID/status?api-version=2018-03-01" \
    -H "Content-Type: application/json")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to get status for NC $NC_ID. HTTP status: $http_status"
    cat /tmp/nc_status_response_$NC_ID.json
    return 1
  fi

  # Parse the status from the response
  nc_status=$(jq -r '.Status' /tmp/nc_status_response_$NC_ID.json)
  if [[ "$nc_status" != "Completed" ]]; then
    echo "NC $NC_ID status is not 'Completed'. Current status: $nc_status"
    return 1
  fi

  echo "NC $NC_ID status is 'Completed'."
}

# Iterate over the nodes and register NCs for each
for index in "${!NC_NODES[@]}"; do
  IFS="|" read -r NODE_NAME NODE_IP POD_NAME <<< "${NC_NODES[index]}"
  CUSTOMER_SUBNET_NAME="${CUSTOMER_SUBNET_NAMES[index]}"

  # Retry logic for creating the NC
  attempt=1
  while [[ $attempt -le $RETRY_COUNT ]]; do
    if create_nc "$NODE_NAME" "$NODE_IP" "$POD_NAME"; then
      echo "Create NC succeeded on attempt $attempt for node: $NODE_NAME."
      break
    fi

    echo "Create NC failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done

  if [[ $attempt -gt $RETRY_COUNT ]]; then
    echo "Failed to create NC for node: $NODE_NAME after $RETRY_COUNT attempts."
    exit 1
  fi

  # Retry logic for polling the NC status
  attempt=1
  while [[ $attempt -le $RETRY_COUNT ]]; do
    if poll_nc_status "$nc_id"; then
      echo "NC status check succeeded on attempt $attempt for node: $NODE_NAME."
      break
    fi

    echo "NC status check failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done

  if [[ $attempt -gt $RETRY_COUNT ]]; then
    echo "Failed to verify NC status for node: $NODE_NAME after $RETRY_COUNT attempts."
    exit 1
  fi
done

echo "All NCs registered and verified successfully!"

############################ Deploy Pods ###########################
# Define an array of pods with their details
PODS=(
  "container2-pod|linuxpool162000000|container2.yaml|cx=vm2"  # Format: POD_NAME|NODE_NAME|POD_YAML|LABEL_SELECTOR TODO: Make it come from inputs
  "container1-pod|linuxpool163000000|container1.yaml|cx=vm1"
)

NAMESPACE="default"  # Replace with the namespace of the DNC deployment
POD_HEALTH_CHECK_RETRY_COUNT=10  # Number of retry attempts
POD_HEALTH_CHECK_RETRY_DELAY=5  # Delay between retries in seconds
export RESOURCE_GROUP=$RESOURCE_GROUP

# Function to deploy a pod
deploy_pod() {
  local POD_NAME=$1
  local NODE_NAME=$2
  local POD_YAML=$3
  local LABEL_SELECTOR=$4

  echo "Deploying pod: $POD_NAME on node: $NODE_NAME with YAML: $POD_YAML"

  # Label the node
  kubectl label node "$NODE_NAME" "$LABEL_SELECTOR" --overwrite

  envsubst < "$POD_YAML" > temp.yaml && mv temp.yaml "$POD_YAML"

  # Apply the pod YAML
  kubectl apply -f "$POD_YAML" -n "$NAMESPACE"

  echo "Pod $POD_NAME deployed"
}

# Main script logic
echo "Starting orchestration..."

# Iterate over the pods and deploy each one
for pod in "${PODS[@]}"; do
  IFS="|" read -r POD_NAME NODE_NAME POD_YAML LABEL_SELECTOR <<< "$pod"

  # Deploy the pod
  deploy_pod "$POD_NAME" "$NODE_NAME" "$POD_YAML" "$LABEL_SELECTOR"

done

# echo "All pods deployed and verified successfully."


############ Stop port forwarding after the operation #############
# Stop port forwarding
echo "Stopping port forwarding..."
kill $PORT_FORWARD_PID

sleep 20

# Verify the process has stopped
if kill -0 $PORT_FORWARD_PID 2>/dev/null; then
  echo "Error: Failed to stop port forwarding"
  exit 1
fi

echo "Port forwarding stopped successfully."