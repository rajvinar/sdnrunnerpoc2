# sal=c4f01b22-f4c8-495a-bd4d-2df90498b81b
# while getopts "a:" opt; do
#   case $opt in
#     a)
#       AUTH_TOKEN="$OPTARG"
#       ;;
#     *)
#       echo "Usage: $0 -a <AUTH_TOKEN>"
#       exit 1
#       ;;
#   esac
# done

# # Check if AUTH_TOKEN is provided
# if [[ -z "$AUTH_TOKEN" ]]; then
#   echo "Error: AUTH_TOKEN is required."
#   echo "Usage: $0 -a <AUTH_TOKEN>"
#   exit 1
# fi

echo "auth to aks..."
az aks get-credentials --resource-group dala-aks-runner8 --name aks --overwrite-existing  --admin || exit 1

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

NAMESPACE="default"  # Replace with the namespace of the DNC deployment
LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
LOCAL_PORT=9000  # Local port to forward
REMOTE_PORT=9000  # Pod's port to forward
DNC_POD="dnc-7f75b67795-cpc5b"

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

###################### Add node to DNC ######################
# # Variables
# DNC_ENDPOINT=$DNC_URL #"https://10.224.0.65:9000"  # Replace with the actual DNC endpoint
# NODE_ID="dncpool151000000"                 # Replace with the actual Node ID
# NODE_API="$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01"
# JSON_CONTENT_TYPE="application/json"

# # Node information payload
# NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": ["10.224.0.65"],
#   "OrchestratorType": "Kubernetes",
#   "InfrastructureNetwork": "52ebbf7f-eb3b-4eea-8ef6-51fe3e2d8bcd",
#   "AZID": "",
#   "NodeType": "",
#   "NodeSet": "",
#   "NumCores": 8,
#   "DualstackEnabled": false
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

################ Join vnet ################
# NETWORK_ID="3f84330f-6410-4996-bb28-78513d2eb093"
# DNC_ENDPOINT=$DNC_URL
# RETRY_COUNT=100  # Number of retry attempts
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

############# Join subnet to DNC #############
# # Variables
# DNC_API_ENDPOINT=$DNC_URL
# CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # Replace with your customer VNet GUID
# CUSTOMER_SUBNET_NAME="delegatedSubnet"  # Replace with your customer subnet name
# API_VERSION="2018-03-01"  # Replace with the API version
# RETRY_COUNT=20  # Number of retry attempts
# RETRY_DELAY=3  # Delay between retries in seconds

# # Function to add a subnet
# add_subnet() {
#   echo "Attempting to add subnet: $CUSTOMER_SUBNET_NAME to VNet: $CUSTOMER_VNET_GUID"
#   echo "AUTH_TOKEN: $AUTH_TOKEN"
#   # Construct the subnet request payload
#   subnet_request=$(cat <<EOF
# {
#   "NetworkID": "$CUSTOMER_VNET_GUID",
#   "SubnetName": "$CUSTOMER_SUBNET_NAME",
#   "AuthenticationToken": "$AUTH_TOKEN"
# }
# EOF
# )

#   # Send the POST request to add the subnet
#   response=$(curl -s -w "%{http_code}" -o /tmp/add_subnet_response.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/subnets/$CUSTOMER_SUBNET_NAME?api-version=$API_VERSION" \
#     -H "Content-Type: application/json" \
#     -d "$subnet_request")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to add subnet $CUSTOMER_SUBNET_NAME. HTTP status: $http_status"
#     cat /tmp/add_subnet_response.json
#     return 1
#   fi

#   echo "Successfully added subnet: $CUSTOMER_SUBNET_NAME"
#   cat /tmp/add_subnet_response.json
# }

# # Function to check the subnet status
# check_subnet_status() {
#   echo "Checking status of subnet: $CUSTOMER_SUBNET_NAME in VNet: $CUSTOMER_VNET_GUID"

#   # Send the GET request to check the subnet status
#   response=$(curl -s -w "%{http_code}" -o /tmp/subnet_status_response.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/subnets/$CUSTOMER_SUBNET_NAME/status?api-version=$API_VERSION" \
#     -H "Content-Type: application/json")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to get status for subnet $CUSTOMER_SUBNET_NAME. HTTP status: $http_status"
#     cat /tmp/subnet_status_response.json
#     return 1
#   fi

#   # Parse the status from the response
#   subnet_status=$(jq -r '.Status' /tmp/subnet_status_response.json)
#   if [[ "$subnet_status" != "Completed" ]]; then
#     echo "Subnet $CUSTOMER_SUBNET_NAME is not in 'Completed' status. Current status: $subnet_status"
#     return 1
#   fi

#   echo "Subnet $CUSTOMER_SUBNET_NAME is in 'Completed' status."
# }

# # Retry logic for adding the subnet
# attempt=1
# while [[ $attempt -le $RETRY_COUNT ]]; do
#   if add_subnet; then
#     echo "Add subnet succeeded on attempt $attempt."
#     break
#   fi

#   echo "Add subnet failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
#   sleep $RETRY_DELAY
#   attempt=$((attempt + 1))
# done

# if [[ $attempt -gt $RETRY_COUNT ]]; then
#   echo "Failed to add subnet after $RETRY_COUNT attempts."
#   exit 1
# fi

# # Retry logic for checking the subnet status
# attempt=1
# while [[ $attempt -le $RETRY_COUNT ]]; do
#   if check_subnet_status; then
#     echo "Subnet status check succeeded on attempt $attempt."
#     exit 0
#   fi

#   echo "Subnet status check failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
#   sleep $RETRY_DELAY
#   attempt=$((attempt + 1))
# done

# echo "Failed to verify subnet status after $RETRY_COUNT attempts."

########################### Create NCs ###########################
# Variables
DNC_API_ENDPOINT=$DNC_URL
CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # Replace with your customer VNet GUID
CUSTOMER_SUBNET_NAME="delegatedSubnet"
NODE_NAME="dncpool151000000"  # Replace with the node name
NC_ID=$(uuidgen)  # Replace with the network container ID
NODE_IP="10.224.0.65"  # Replace with the node IP
POD_NAME="container1-pod"  # Replace with the pod name
POD_NAMESPACE="default"  # Replace with the pod namespace
RETRY_COUNT=20  # Number of retry attempts
RETRY_DELAY=3  # Delay between retries in seconds
IP_CONSTRAINT=""
NODE_CONSTRAINT=""  # Replace with the node constraint if needed
SECONDARY_IP_COUNT=0  # Number of secondary IPs to allocate
PRIMARY_IP_PREFIX_BITS=0  # Primary IP prefix bits
CONTAINER_TYPE="AzureContainerInstance"  # Container type
OWNER_ID=""  # Replace with the owner ID
RESERVATION_ID=""  # Replace with the reservation ID if needed
RESERVATION_SET_ID=""  # Replace with the reservation set ID if needed
IFACE_ID=$NODE_IP  # Replace with the interface ID if needed
HOST_TO_NC=false  # Allow host to NC communication
NC_TO_HOST=false  # Allow NC to host communication


# Function to create a network container (NC)
create_nc() {
  echo "Attempting to create NC: $NC_ID on node: $NODE_NAME"

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
    "InterfaceID": "$IFACE_ID",
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
    "NodeID": "$NODE_ID",
    "InterfaceID": "$IFACE_ID",
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
  response=$(curl -s -w "%{http_code}" -o /tmp/create_nc_response.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID?api-version=2018-03-01" \
    -H "Content-Type: application/json" \
    -d "$nc_request")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful or if there was a conflict
  if [[ "$http_status" -ne 200 && "$http_status" -ne 409 ]]; then
    echo "Failed to create NC $NC_ID. HTTP status: $http_status"
    cat /tmp/create_nc_response.json
    return 1
  fi

  echo "Successfully created NC: $NC_ID"
  cat /tmp/create_nc_response.json
}

# Function to poll the NC status
poll_nc_status() {
  echo "Polling status of NC: $NC_ID"

  # Send the GET request to check the NC status
  response=$(curl -s -w "%{http_code}" -o /tmp/nc_status_response.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID/status?api-version=2018-03-01" \
    -H "Content-Type: application/json")

  # Extract HTTP status code
  http_status=$(tail -n1 <<< "$response")

  # Check if the request was successful
  if [[ "$http_status" -ne 200 ]]; then
    echo "Failed to get status for NC $NC_ID. HTTP status: $http_status"
    cat /tmp/nc_status_response.json
    return 1
  fi

  # Parse the status from the response
  nc_status=$(jq -r '.Status' /tmp/nc_status_response.json)
  if [[ "$nc_status" != "Completed" ]]; then
    echo "NC $NC_ID status is not 'Completed'. Current status: $nc_status"
    return 1
  fi

  echo "NC $NC_ID status is 'Completed'."
}


attempt=1
while [[ $attempt -le $RETRY_COUNT ]]; do
  if create_nc; then
    echo "Create NC succeeded on attempt $attempt."
    break
  fi

  echo "Create NC failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
  sleep "$RETRY_DELAY"
  attempt=$((attempt + 1))
done

if [[ $attempt -gt $RETRY_COUNT ]]; then
  echo "Failed to create NC after $RETRY_COUNT attempts."
  exit 1
fi

# Retry logic for polling the NC status
attempt=1
while [[ $attempt -le $RETRY_COUNT ]]; do
  if poll_nc_status; then
    echo "NC status check succeeded on attempt $attempt."
    exit 0
  fi

  echo "NC status check failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
  sleep "$RETRY_DELAY"
  attempt=$((attempt + 1))
done

echo "Failed to verify NC status after $RETRY_COUNT attempts."

############################ Deploy Pods ###########################
# POD_HEALTH_CHECK_RETRY_COUNT=10  # Number of retry attempts
# POD_HEALTH_CHECK_RETRY_DELAY=5  # Delay between retries in seconds
# # Function to deploy pods
# deploy_pods() {
#   local node_name=$1
#   local os=$2
#   local pod_name=$3

#   echo "Deploying pod $pod_name on node $node_name"
#   pod_yaml=""
#   if [[ "$os" == "linux" ]]; then
#     pod_yaml=$GOLDPINGER_LINUX_YAML
#   elif [[ "$os" == "windows" ]]; then
#     pod_yaml=$GOLDPINGER_WINDOWS_YAML
#   fi

#   # Apply the pod YAML with nodeSelector
#   kubectl apply -f "$pod_yaml" -n "$NAMESPACE" --dry-run=client -o yaml | \
#     kubectl label --overwrite -f - "nodeSelector.$NODE_LABEL_KEY=$node_name"
#   echo "Pod $pod_name deployed successfully"
# }

# # Function to check pod health
# check_pod_health() {
#   echo "Checking pod health..."
#   for ((attempt = 1; attempt <= POD_HEALTH_CHECK_RETRY_COUNT; attempt++)); do
#     pod_list=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json)
#     pod_count=$(echo "$pod_list" | jq '.items | length')

#     if [[ "$pod_count" -eq 0 ]]; then
#       echo "No pods scheduled. Retrying in $POD_HEALTH_CHECK_RETRY_DELAY seconds..."
#       sleep "$POD_HEALTH_CHECK_RETRY_DELAY"
#       continue
#     fi

#     all_ready=true
#     for pod in $(echo "$pod_list" | jq -r '.items[].status.phase'); do
#       if [[ "$pod" != "Running" ]]; then
#         all_ready=false
#         break
#       fi
#     done

#     if [[ "$all_ready" == true ]]; then
#       echo "All pods are healthy and running."
#       return 0
#     fi

#     echo "Some pods are not ready. Retrying in $POD_HEALTH_CHECK_RETRY_DELAY seconds..."
#     sleep "$POD_HEALTH_CHECK_RETRY_DELAY"
#   done

#   echo "Failed to verify pod health after $POD_HEALTH_CHECK_RETRY_COUNT attempts."
#   exit 1
# }

# # Main script logic
# echo "Starting orchestration..."

# # Example: Create NCs for two nodes
# create_ncs "node1" "linux" 2 0
# create_ncs "node2" "windows" 2 2

# # Example: Deploy pods for the nodes
# deploy_pods "node1" "linux" "goldpinger-linux-0"
# deploy_pods "node2" "windows" "goldpinger-windows-0"

# # Check pod health
# check_pod_health

# echo "Orchestration completed successfully."

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