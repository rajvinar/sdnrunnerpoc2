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
az aks get-credentials --resource-group dala-aks-runner23 --name aks --overwrite-existing  --admin || exit 1

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

########### Port Forwarding Setup ###########
DNC_POD=$(kubectl get pods -n default -l app=dnc -o jsonpath='{.items[0].metadata.name}')
echo "DNC Pod Name: $DNC_POD"
# DNC_POD=$DNC_POD_NAME
NAMESPACE="default"  # Replace with the namespace of the DNC deployment
LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
LOCAL_PORT=9000  # Local port to forward
REMOTE_PORT=9000  # Pod's port to forward

# DNC_POD="dnc-7f75b67795-cpc5b" # TODO: make it from az command

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


############################ Deploy Pods ###########################
# Define an array of pods with their details
PODS=(
  "container2-pod|linuxpool180000000|container2.yaml|cx=vm2"  # Format: POD_NAME|NODE_NAME|POD_YAML|LABEL_SELECTOR TODO: Make it come from inputs
  "container1-pod|linuxpool181000000|container1.yaml|cx=vm1"
)

NAMESPACE="default"  # Replace with the namespace of the DNC deployment
POD_HEALTH_CHECK_RETRY_COUNT=10  # Number of retry attempts
POD_HEALTH_CHECK_RETRY_DELAY=5  # Delay between retries in seconds


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

PRIVATE_IPS=()
# Iterate over the pods and deploy each one
for pod in "${PODS[@]}"; do
  IFS="|" read -r POD_NAME NODE_NAME POD_YAML LABEL_SELECTOR <<< "$pod"

  # Deploy the pod
  deploy_pod "$POD_NAME" "$NODE_NAME" "$POD_YAML" "$LABEL_SELECTOR"

  sleep 60

  # Get the private IP of the pod
  PRIVATE_IP=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
  echo "Private IP of Pod $POD_NAME: $PRIVATE_IP"

  # Add the private IP to the array
  PRIVATE_IPS+=("$POD_NAME|$PRIVATE_IP")
done

echo "{\"privateIPs\": $(printf '%s\n' "${PRIVATE_IPS[@]}" | jq -R . | jq -s .)}" > $AZ_SCRIPTS_OUTPUT_PATH
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


# # Create Worker node pool(s)
# echo "Creating Worker node pool(s)..."
# WORKER_VMSSES=("linuxpool190") # TODO : make it come from inputs
# INSTANCE_NAMES=()
# # Loop through VMSS names and create VMSS
# for VMSS_NAME in "${WORKER_VMSSES[@]}"; do
#     EXTENSION_NAME="NodeJoin-${VMSS_NAME}"  # Unique extension name for each VMSS
#     echo "Creating VMSS: $VMSS_NAME with extension: $EXTENSION_NAME"
#     az deployment group create \
#         --name "vmss-deployment-${VMSS_NAME}" \
#         --resource-group "$RESOURCE_GROUP" \
#         --template-file "$BICEP_TEMPLATE_PATH" \
#         --parameters vnetname="$INFRA_VNET_NAME" \
#                      subnetname="$INFRA_SUBNET_NAME" \
#                      name="$VMSS_NAME" \
#                      adminPassword="$ADMIN_PASSWORD" \
#                      vnetrgname="$RESOURCE_GROUP" \
#                      vmsssku="Standard_E8s_v3" \
#                      location="westus" \
#                      extensionName="$EXTENSION_NAME" > "./lin-script-${VMSS_NAME}.log" 2>&1 &
#     wait

#     INSTANCE_IDS=$(az vmss list-instances --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" --query "[].instanceId" -o tsv)
#     for INSTANCE_ID in $INSTANCE_IDS; do
#         INSTANCE_NAME=$(az vmss get-instance-view --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" --instance-id "$INSTANCE_ID" --query "osProfile.computerName" -o tsv)
#         INSTANCE_NAMES+=("$INSTANCE_NAME")
#     done
# done

# sleep 240

# # Label the worker nodes and deploy the cns ConfigMap and DaemonSet
# echo "Labeling worker nodes..."
# WORKER_NODES=("linuxpool190000000") # TODO : make it come from inpu
# # Label key and value
# LABEL_KEY="kubernetes.azure.com/mode"
# LABEL_VALUE="user"
# # Loop through each node and apply the label
# for NODE in "${WORKER_NODES[@]}"; do
#   kubectl label node "$NODE" "$LABEL_KEY=$LABEL_VALUE" --overwrite
#   kubectl label node "$NODE" node-type=cnscni --overwrite
#   echo "Successfully labeled node: $NODE"
# done

# # Assign MI to worker nodes to access runner worker image
# echo "Assigning Managed Identity to worker nodes..."
# for VMSS in "${WORKER_VMSSES[@]}"; do
#     az vmss identity assign --name $VMSS --resource-group $RESOURCE_GROUP --identities $AKS_KUBERNETES_SERVICE_MANAGED_IDENTITY_CLIENT_ID
#     wait
# done



# DNC_POD=$(kubectl get pods -n default -l app=dnc -o jsonpath='{.items[0].metadata.name}')
# echo "DNC Pod Name: $DNC_POD"
# # DNC_POD=$DNC_POD_NAME
# NAMESPACE="default"  # Replace with the namespace of the DNC deployment
# LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
# LOCAL_PORT=9000  # Local port to forward
# REMOTE_PORT=9000  # Pod's port to forward

# # DNC_POD="dnc-7f75b67795-cpc5b" # TODO: make it from az command

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




# NODES=(
#   "linuxpool190000000"
# )
# # Initialize an empty array to store the formatted NODES
# FORMATTED_NODES=()

# # Loop through each node in the NODES array
# for NODE in "${NODES[@]}"; do
#   # Get the internal IP of the node using kubectl
#   NODE_IP=$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
  
#   # Append the formatted NODE_ID|NODE_IP to the FORMATTED_NODES array
#   FORMATTED_NODES+=("$NODE|$NODE_IP")
# done

# # Update the NODES array with the formatted values
# NODES=("${FORMATTED_NODES[@]}")


# DNC_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
# JSON_CONTENT_TYPE="application/json"

# # Function to register a node
# register_node() {
#   local NODE_ID=$1
#   local NODE_IP=$2

#   echo "Registering node: $NODE_ID with IP: $NODE_IP"

#   # Node information payload
#   NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": ["$NODE_IP"],
#   "OrchestratorType": "Kubernetes",
#   "InfrastructureNetwork": "52ebbf7f-eb3b-4eea-8ef6-51fe3e2d8bcd",
#   "AZID": "",
#   "NodeType": "",
#   "NodeSet": "",
#   "NumCores": 8,
#   "DualstackEnabled": false
# }
# EOF
#   )

#   # Send HTTP POST request to add the node
#   response=$(curl -s -w "%{http_code}" -o /tmp/add_node_response_$NODE_ID.json -X POST "$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01" \
#     -H "Content-Type: $JSON_CONTENT_TYPE" \
#     -d "$NODE_INFO_JSON")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to add node $NODE_ID. HTTP status: $http_status"
#     cat /tmp/add_node_response_$NODE_ID.json
#     return 1
#   fi

#   echo "Node $NODE_ID added successfully!"
#   cat /tmp/add_node_response_$NODE_ID.json
# }

# # Iterate over the nodes and register each one
# for node in "${NODES[@]}"; do
#   IFS="|" read -r NODE_ID NODE_IP <<< "$node"
#   if ! register_node "$NODE_ID" "$NODE_IP"; then
#     echo "Error: Failed to register node $NODE_ID"
#     exit 1
#   fi
# done

# echo "All nodes registered successfully!"


# CUSTOMER_VNET_GUID="b4d2d13d-ee06-4eff-ba82-95d182f40a71"
# DNC_API_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
# POD_NAMESPACE="default"  # Replace with the pod namespace
# RETRY_COUNT=20  # Number of retry attempts
# RETRY_DELAY=3  # Delay between retries in seconds
# IP_CONSTRAINT=""
# NODE_CONSTRAINT=""
# SECONDARY_IP_COUNT=0
# PRIMARY_IP_PREFIX_BITS=0
# CONTAINER_TYPE="AzureContainerInstance"
# OWNER_ID=""
# RESERVATION_ID=""
# RESERVATION_SET_ID=""
# HOST_TO_NC=false
# NC_TO_HOST=false
# nc_id=""

# # NC_NODES=(
# #   "linuxpool160000000|10.224.0.76|container1-pod"  # Format: NODE_NAME|NODE_IP|POD_NAME TODO: Make it come from inputs
# #   "linuxpool161000000|10.224.0.78|container2-pod"
# # )
# # CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # TODO: make it come from inputs
# # Define an array of POD_NAMES corresponding to the nodes
# POD_NAMES=(
#   #"container1-pod"
#   "container2-pod"
# )

# # Initialize an empty array to store the updated NODES
# NC_NODES=()
# # Loop through the NODES array and append the corresponding POD_NAME
# for i in "${!NODES[@]}"; do
#   NODE="${NODES[i]}"
#   POD_NAME="${POD_NAMES[i]}"
#   NC_NODES+=("$NODE|$POD_NAME")
# done
# CUSTOMER_SUBNET_NAMES=(
#   "delegatedSubnet"
#   # "delegatedSubnet1"
# )

# # Function to create a network container (NC)
# create_nc() {
#   local NODE_NAME=$1
#   local NODE_IP=$2
#   local POD_NAME=$3
#   local CUSTOMER_SUBNET_NAME=$4
#   local NC_ID=$(uuidgen)  # Generate a unique NC ID
#   nc_id="$NC_ID"
#   echo "Attempting to create NC: $NC_ID on node: $NODE_NAME with pod: $POD_NAME"

#   # Construct the NC request payload
#   if [[ -z "$RESERVATION_ID" && -z "$RESERVATION_SET_ID" ]]; then
#     # V2 request
#     nc_request=$(cat <<EOF
# {
#   "AllocationRequest": {
#     "SubnetName": "$CUSTOMER_SUBNET_NAME",
#     "IPConstraint": "$IP_CONSTRAINT",
#     "NodeConstraint": "$NODE_CONSTRAINT",
#     "SecondaryIPCount": $SECONDARY_IP_COUNT,
#     "PrimaryIPPrefixBits": $PRIMARY_IP_PREFIX_BITS
#   },
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$NODE_IP",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
#     )
#   else
#     # V1 request
#     nc_request=$(cat <<EOF
# {
#   "ReservationID": "$RESERVATION_ID",
#   "ReservationSetID": "$RESERVATION_SET_ID",
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$NODE_IP",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
#     )
#   fi

#   echo "NC request payload: $nc_request"

#   # Send the POST request to create the NC
#   response=$(curl -s -w "%{http_code}" -o /tmp/create_nc_response_$NC_ID.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID?api-version=2018-03-01" \
#     -H "Content-Type: application/json" \
#     -d "$nc_request")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful or if there was a conflict
#   if [[ "$http_status" -ne 200 && "$http_status" -ne 409 ]]; then
#     echo "Failed to create NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/create_nc_response_$NC_ID.json
#     return 1
#   fi

#   echo "Successfully created NC: $NC_ID"
#   cat /tmp/create_nc_response_$NC_ID.json
# }

# # Function to poll the NC status
# poll_nc_status() {
#   local NC_ID=$1

#   echo "Polling status of NC: $NC_ID"

#   # Send the GET request to check the NC status
#   response=$(curl -s -w "%{http_code}" -o /tmp/nc_status_response_$NC_ID.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID/status?api-version=2018-03-01" \
#     -H "Content-Type: application/json")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to get status for NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/nc_status_response_$NC_ID.json
#     return 1
#   fi

#   # Parse the status from the response
#   nc_status=$(jq -r '.Status' /tmp/nc_status_response_$NC_ID.json)
#   if [[ "$nc_status" != "Completed" ]]; then
#     echo "NC $NC_ID status is not 'Completed'. Current status: $nc_status"
#     return 1
#   fi

#   echo "NC $NC_ID status is 'Completed'."
# }

# # Iterate over the nodes and register NCs for each
# for index in "${!NC_NODES[@]}"; do
#   IFS="|" read -r NODE_NAME NODE_IP POD_NAME <<< "${NC_NODES[index]}"
#   CUSTOMER_SUBNET_NAME="${CUSTOMER_SUBNET_NAMES[index]}"

#   # Retry logic for creating the NC
#   attempt=1
#   while [[ $attempt -le $RETRY_COUNT ]]; do
#     if create_nc "$NODE_NAME" "$NODE_IP" "$POD_NAME" "$CUSTOMER_SUBNET_NAME"; then
#       echo "Create NC succeeded on attempt $attempt for node: $NODE_NAME."
#       break
#     fi

#     echo "Create NC failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
#     sleep "$RETRY_DELAY"
#     attempt=$((attempt + 1))
#   done

#   if [[ $attempt -gt $RETRY_COUNT ]]; then
#     echo "Failed to create NC for node: $NODE_NAME after $RETRY_COUNT attempts."
#     exit 1
#   fi

#   # Retry logic for polling the NC status
#   attempt=1
#   while [[ $attempt -le $RETRY_COUNT ]]; do
#     if poll_nc_status "$nc_id"; then
#       echo "NC status check succeeded on attempt $attempt for node: $NODE_NAME."
#       break
#     fi

#     echo "NC status check failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
#     sleep "$RETRY_DELAY"
#     attempt=$((attempt + 1))
#   done

#   if [[ $attempt -gt $RETRY_COUNT ]]; then
#     echo "Failed to verify NC status for node: $NODE_NAME after $RETRY_COUNT attempts."
#     exit 1
#   fi
# done

# echo "All NCs registered and verified successfully!"













# NAMESPACE="default"  # Replace with the namespace of the DNC deployment
# LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
# LOCAL_PORT=9000  # Local port to forward
# REMOTE_PORT=9000  # Pod's port to forward
# DNC_POD="dnc-7f75b67795-cpc5b"

# # Start port forwarding
# echo "Starting port forwarding from localhost:$LOCAL_PORT to $DNC_POD:$REMOTE_PORT..."
# kubectl port-forward -n "$NAMESPACE" pod/"$DNC_POD" "$LOCAL_PORT:$REMOTE_PORT" & PORT_FORWARD_PID=$!

# # Wait for port forwarding to establish
# sleep 10

# # Check if the port forwarding process is running
# if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
#   echo "Error: Port forwarding failed to start"
#   exit 1
# fi

# # Log the forwarded URL
# DNC_URL="http://localhost:$LOCAL_PORT"
# echo "Successfully port forwarded to DNC: $DNC_URL"

# ##############################################################
# # Define an array of pods with their details
# PODS=(
#   "container1-pod|linuxpool180000000|container1.yaml|cx=vm1|container1-service"  # Format: POD_NAME|NODE_NAME|POD_YAML|LABEL_SELECTOR TODO: Make it come from inputs
#   "container2-pod|linuxpool181000000|container2.yaml|cx=vm2|container2-service"
# )

# NAMESPACE="default"  # Replace with the namespace of the DNC deployment
# POD_HEALTH_CHECK_RETRY_COUNT=10  # Number of retry attempts
# POD_HEALTH_CHECK_RETRY_DELAY=5  # Delay between retries in seconds
# export RESOURCE_GROUP="dala-aks-runner8"

# # Function to deploy a pod
# deploy_pod() {
#   local POD_NAME=$1
#   local NODE_NAME=$2
#   local POD_YAML=$3
#   local LABEL_SELECTOR=$4

#   echo "Deploying pod: $POD_NAME on node: $NODE_NAME with YAML: $POD_YAML"

#   # Label the node
#   kubectl label node "$NODE_NAME" "$LABEL_SELECTOR" --overwrite

#   envsubst < "$POD_YAML" > temp.yaml && mv temp.yaml "$POD_YAML"

#   # Apply the pod YAML
#   kubectl apply -f "$POD_YAML" -n "$NAMESPACE"

#   echo "Pod $POD_NAME deployed"
# }

# # Main script logic
# echo "Starting orchestration..."

# # Iterate over the pods and deploy each one
# for pod in "${PODS[@]}"; do
#   IFS="|" read -r POD_NAME NODE_NAME POD_YAML LABEL_SELECTOR SERVICE_NAME <<< "$pod"

#   # Deploy the pod
#   deploy_pod "$POD_NAME" "$NODE_NAME" "$POD_YAML" "$LABEL_SELECTOR"

#   # Get the private IP of the pod
#   PRIVATE_IP=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
#   echo "Private IP of Pod $POD_NAME: $PRIVATE_IP"

#   # Get the public IP and FQDN of the service
#   PUBLIC_IP=$(kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#   PUBLIC_FQDN=$(kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

#   echo "Public IP of Service $SERVICE_NAME: $PUBLIC_IP"
#   echo "Public FQDN of Service $SERVICE_NAME: $PUBLIC_FQDN"

# done
######################################


# echo "All pods deployed and verified successfully."

############################################################
# DNC_API_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
# POD_NAMESPACE="default"  # Replace with the pod namespace
# RETRY_COUNT=20  # Number of retry attempts
# RETRY_DELAY=3  # Delay between retries in seconds
# IP_CONSTRAINT=""
# NODE_CONSTRAINT=""
# SECONDARY_IP_COUNT=0
# PRIMARY_IP_PREFIX_BITS=0
# CONTAINER_TYPE="AzureContainerInstance"
# OWNER_ID=""
# RESERVATION_ID=""
# RESERVATION_SET_ID=""
# HOST_TO_NC=false
# NC_TO_HOST=false
# nc_id=""

# NC_NODES=(
#   "linuxpool180000000|10.224.0.90|container1-pod"  # Format: NODE_NAME|NODE_IP|POD_NAME TODO: Make it come from inputs
#   "linuxpool181000000|10.224.0.94|container2-pod"
# )
# CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # TODO: make it come from inputs
# CUSTOMER_SUBNET_NAME="delegatedSubnet" # TODO: make it come from inputs


# # Function to create a network container (NC)
# create_nc() {
#   local NODE_NAME=$1
#   local NODE_IP=$2
#   local POD_NAME=$3
#   local NC_ID=$(uuidgen)  # Generate a unique NC ID
#   nc_id="$NC_ID"  # Store the NC ID for later use
#   echo "Attempting to create NC: $NC_ID on node: $NODE_NAME with pod: $POD_NAME"

#   # Construct the NC request payload
#   if [[ -z "$RESERVATION_ID" && -z "$RESERVATION_SET_ID" ]]; then
#     # V2 request
#     nc_request=$(cat <<EOF
# {
#   "AllocationRequest": {
#     "SubnetName": "$CUSTOMER_SUBNET_NAME",
#     "IPConstraint": "$IP_CONSTRAINT",
#     "NodeConstraint": "$NODE_CONSTRAINT",
#     "SecondaryIPCount": $SECONDARY_IP_COUNT,
#     "PrimaryIPPrefixBits": $PRIMARY_IP_PREFIX_BITS
#   },
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$NODE_IP",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
#     )
#   else
#     # V1 request
#     nc_request=$(cat <<EOF
# {
#   "ReservationID": "$RESERVATION_ID",
#   "ReservationSetID": "$RESERVATION_SET_ID",
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$NODE_IP",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
#     )
#   fi

#   echo "NC request payload: $nc_request"

#   # Send the POST request to create the NC
#   response=$(curl -s -w "%{http_code}" -o /tmp/create_nc_response_$NC_ID.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID?api-version=2018-03-01" \
#     -H "Content-Type: application/json" \
#     -d "$nc_request")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful or if there was a conflict
#   if [[ "$http_status" -ne 200 && "$http_status" -ne 409 ]]; then
#     echo "Failed to create NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/create_nc_response_$NC_ID.json
#     return 1
#   fi

#   echo "Successfully created NC: $NC_ID"
#   cat /tmp/create_nc_response_$NC_ID.json
# }

# # Function to poll the NC status
# poll_nc_status() {
#   local NC_ID=$1

#   echo "Polling status of NC: $NC_ID"

#   # Send the GET request to check the NC status
#   response=$(curl -s -w "%{http_code}" -o /tmp/nc_status_response_$NC_ID.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID/status?api-version=2018-03-01" \
#     -H "Content-Type: application/json")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to get status for NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/nc_status_response_$NC_ID.json
#     return 1
#   fi

#   # Parse the status from the response
#   nc_status=$(jq -r '.Status' /tmp/nc_status_response_$NC_ID.json)
#   if [[ "$nc_status" != "Completed" ]]; then
#     echo "NC $NC_ID status is not 'Completed'. Current status: $nc_status"
#     return 1
#   fi

#   echo "NC $NC_ID status is 'Completed'."
# }

# # Iterate over the nodes and register NCs for each
# for node in "${NC_NODES[@]}"; do
#   IFS="|" read -r NODE_NAME NODE_IP POD_NAME <<< "$node"

#   # Retry logic for creating the NC
#   attempt=1
#   while [[ $attempt -le $RETRY_COUNT ]]; do
#     if create_nc "$NODE_NAME" "$NODE_IP" "$POD_NAME"; then
#       echo "Create NC succeeded on attempt $attempt for node: $NODE_NAME."
#       break
#     fi

#     echo "Create NC failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
#     sleep "$RETRY_DELAY"
#     attempt=$((attempt + 1))
#   done

#   if [[ $attempt -gt $RETRY_COUNT ]]; then
#     echo "Failed to create NC for node: $NODE_NAME after $RETRY_COUNT attempts."
#     exit 1
#   fi

#   # Retry logic for polling the NC status
#   attempt=1
#   while [[ $attempt -le $RETRY_COUNT ]]; do
#     if poll_nc_status "$nc_id"; then
#       echo "NC status check succeeded on attempt $attempt for node: $NODE_NAME."
#       break
#     fi

#     echo "NC status check failed on attempt $attempt for node: $NODE_NAME and nc: $nc_id. Retrying in $RETRY_DELAY seconds..."
#     sleep "$RETRY_DELAY"
#     attempt=$((attempt + 1))
#   done

#   if [[ $attempt -gt $RETRY_COUNT ]]; then
#     echo "Failed to verify NC status for node: $NODE_NAME after $RETRY_COUNT attempts."
#     exit 1
#   fi
# done

# echo "All NCs registered and verified successfully!"


#############################################################################
# # Define an array of nodes with their details
# NODES=(
#   "linuxpool180000000|10.224.0.90"  # Format: NODE_ID|NODE_IP TODO: Make it come from inputs
#   "linuxpool181000000|10.224.0.94"
# )

# DNC_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
# JSON_CONTENT_TYPE="application/json"

# # Function to register a node
# register_node() {
#   local NODE_ID=$1
#   local NODE_IP=$2

#   echo "Registering node: $NODE_ID with IP: $NODE_IP"

#   # Node information payload
#   NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": ["$NODE_IP"],
#   "OrchestratorType": "Kubernetes",
#   "InfrastructureNetwork": "52ebbf7f-eb3b-4eea-8ef6-51fe3e2d8bcd",
#   "AZID": "",
#   "NodeType": "",
#   "NodeSet": "",
#   "NumCores": 8,
#   "DualstackEnabled": false
# }
# EOF
#   )

#   # Send HTTP POST request to add the node
#   response=$(curl -s -w "%{http_code}" -o /tmp/add_node_response_$NODE_ID.json -X POST "$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01" \
#     -H "Content-Type: $JSON_CONTENT_TYPE" \
#     -d "$NODE_INFO_JSON")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to add node $NODE_ID. HTTP status: $http_status"
#     cat /tmp/add_node_response_$NODE_ID.json
#     return 1
#   fi

#   echo "Node $NODE_ID added successfully!"
#   cat /tmp/add_node_response_$NODE_ID.json
# }

# # Iterate over the nodes and register each one
# for node in "${NODES[@]}"; do
#   IFS="|" read -r NODE_ID NODE_IP <<< "$node"
#   if ! register_node "$NODE_ID" "$NODE_IP"; then
#     echo "Error: Failed to register node $NODE_ID"
#     exit 1
#   fi
# done

# echo "All nodes registered successfully!"
############################################################

# echo "Labeling worker nodes..."
# WORKER_NODES=("linuxpool180000000" "linuxpool181000000") # TODO : make it come from inputs
# # Label key and value
# LABEL_KEY="kubernetes.azure.com/mode"
# LABEL_VALUE="user"
# # Loop through each node and apply the label
# for NODE in "${WORKER_NODES[@]}"; do
#   kubectl label node "$NODE" "$LABEL_KEY=$LABEL_VALUE" --overwrite
#   kubectl label node "$NODE" node-type=cnscni --overwrite
#   echo "Successfully labeled node: $NODE"
# done


# WORKER_VMSSES=("linuxpool180" "linuxpool181") # TODO : make it come from inputs
# MANAGED_IDENTITY="/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/dala-aks-runner8/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aksClusterKubeletIdentity"
# # Assign MI to worker nodes to access runner worker image
# echo "Assigning Managed Identity to worker nodes..."
# for VMSS in "${WORKER_VMSSES[@]}"; do
#     # echo "Assigning Managed Identity to VMSS: $VMSS"
#     # az vmss identity assign --name $VMSS --resource-group dala-aks-runner8 --identities /subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/dala-aks-runner8/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aksClusterKubeletIdentity
#     # echo "Successfully assigned Managed Identity to VMSS: $VMSS"
#        echo "Checking Managed Identity for VMSS: $VMSS"

#     # Check if the VMSS already has the managed identity
#     IDENTITY_CHECK=$(az vmss show --name "$VMSS" --resource-group dala-aks-runner8 --query "identity.userAssignedIdentities['$MANAGED_IDENTITY']" --output tsv)

#     if [[ -n "$IDENTITY_CHECK" ]]; then
#         echo "Managed Identity is already assigned to VMSS: $VMSS. Skipping assignment."
#     else
#         echo "Managed Identity not found for VMSS: $VMSS. Assigning now..."
#         az vmss identity assign --name "$VMSS" --resource-group dala-aks-runner8 --identities "$MANAGED_IDENTITY"
#         echo "Successfully assigned Managed Identity to VMSS: $VMSS"
#     fi
# done

# # echo "Deploying cns ConfigMap and DaemonSet..."
# # Deploy the cns ConfigMap
# echo "Deploying azure_cns_configmap.yaml to namespace default..."
# kubectl apply -f azure_cns_configmap.yaml -n default

# # Deploy the cns DaemonSet
# echo "Deploying azure_cns_daemonset.yaml to namespace default..."
# kubectl apply -f azure_cns_daemonset.yaml -n default












############# Delete node in DNC #############
# # Variables
# DNC_API_ENDPOINT=$DNC_URL  # Replace with your DNC API endpoint
# NODE_ID="linuxpool151000000"  # Replace with the node ID to delete
# API_VERSION="2018-03-01"  # API version

# # Construct the Node API URL
# NODE_API_URL="$DNC_API_ENDPOINT/nodes/$NODE_ID?api-version=$API_VERSION"

# # Function to delete a node
# delete_node() {
#   echo "Attempting to delete node: $NODE_ID"

#   # Send the DELETE request
#   response=$(curl -s -w "%{http_code}" -o /tmp/delete_node_response.json -X DELETE "$NODE_API_URL")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to delete node $NODE_ID. HTTP status: $http_status"
#     cat /tmp/delete_node_response.json
#     exit 1
#   fi

#   echo "Successfully deleted node: $NODE_ID"
#   cat /tmp/delete_node_response.json
# }

# # Call the function
# delete_node

# sleep 10

###################### Add node to DNC ######################
# Variables
# NODE_ID="linuxpool15000000"
# NODE_IP="10.224.0.69"
# NODE_ID="linuxpool163000000"
# NODE_IP="10.224.0.86"

# DNC_ENDPOINT=$DNC_URL #"https://10.224.0.65:9000"  # Replace with the actual DNC endpoint
# NODE_API="$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01"
# JSON_CONTENT_TYPE="application/json"

# # Node information payload
# NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": ["$NODE_IP"],
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


###########new code #############
# # Define an array of nodes with their details
# NODES=(
#   "linuxpool160000000|10.224.0.76"  # Format: NODE_ID|NODE_IP
#   "linuxpool161000000|10.224.0.78"
# )

# DNC_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
# JSON_CONTENT_TYPE="application/json"

# # Function to register a node
# register_node() {
#   local NODE_ID=$1
#   local NODE_IP=$2

#   echo "Registering node: $NODE_ID with IP: $NODE_IP"

#   # Node information payload
#   NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": ["$NODE_IP"],
#   "OrchestratorType": "Kubernetes",
#   "InfrastructureNetwork": "52ebbf7f-eb3b-4eea-8ef6-51fe3e2d8bcd",
#   "AZID": "",
#   "NodeType": "",
#   "NodeSet": "",
#   "NumCores": 8,
#   "DualstackEnabled": false
# }
# EOF
#   )

#   # Send HTTP POST request to add the node
#   response=$(curl -s -w "%{http_code}" -o /tmp/add_node_response_$NODE_ID.json -X POST "$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01" \
#     -H "Content-Type: $JSON_CONTENT_TYPE" \
#     -d "$NODE_INFO_JSON")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to add node $NODE_ID. HTTP status: $http_status"
#     cat /tmp/add_node_response_$NODE_ID.json
#     return 1
#   fi

#   echo "Node $NODE_ID added successfully!"
#   cat /tmp/add_node_response_$NODE_ID.json
# }

# # Iterate over the nodes and register each one
# for node in "${NODES[@]}"; do
#   IFS="|" read -r NODE_ID NODE_IP <<< "$node"
#   if ! register_node "$NODE_ID" "$NODE_IP"; then
#     echo "Error: Failed to register node $NODE_ID"
#     exit 1
#   fi
# done

# echo "All nodes registered successfully!"

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
# # Variables
# NODE_NAME="linuxpool15000000"  # Replace with the node name
# NODE_IP="10.224.0.69"  # Replace with the node IP
# POD_NAME="container1-pod"  # Replace with the pod name

# NODE_NAME="linuxpool163000000"  # Replace with the node name
# NODE_IP="10.224.0.86"  # Replace with the node IP
# POD_NAME="container1-pod"  # Replace with the pod name

# DNC_API_ENDPOINT=$DNC_URL
# CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # Replace with your customer VNet GUID
# CUSTOMER_SUBNET_NAME="delegatedSubnet"
# NC_ID=$(uuidgen)  # Replace with the network container ID
# POD_NAMESPACE="default"  # Replace with the pod namespace
# RETRY_COUNT=20  # Number of retry attempts
# RETRY_DELAY=3  # Delay between retries in seconds
# IP_CONSTRAINT=""
# NODE_CONSTRAINT=""  # Replace with the node constraint if needed
# SECONDARY_IP_COUNT=0  # Number of secondary IPs to allocate
# PRIMARY_IP_PREFIX_BITS=0  # Primary IP prefix bits
# CONTAINER_TYPE="AzureContainerInstance"  # Container type
# OWNER_ID=""  # Replace with the owner ID
# RESERVATION_ID=""  # Replace with the reservation ID if needed
# RESERVATION_SET_ID=""  # Replace with the reservation set ID if needed
# IFACE_ID=$NODE_IP  # Replace with the interface ID if needed
# HOST_TO_NC=false  # Allow host to NC communication
# NC_TO_HOST=false  # Allow NC to host communication


# # Function to create a network container (NC)
# create_nc() {
#   echo "Attempting to create NC: $NC_ID on node: $NODE_NAME"

# # Construct the NC request payload
# if [[ -z "$RESERVATION_ID" && -z "$RESERVATION_SET_ID" ]]; then
#   # V2 request
#   nc_request=$(cat <<EOF
# {
#   "AllocationRequest": {
#     "SubnetName": "$CUSTOMER_SUBNET_NAME",
#     "IPConstraint": "$IP_CONSTRAINT",
#     "NodeConstraint": "$NODE_CONSTRAINT",
#     "SecondaryIPCount": $SECONDARY_IP_COUNT,
#     "PrimaryIPPrefixBits": $PRIMARY_IP_PREFIX_BITS
#   },
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$IFACE_ID",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
# )
# else
#   # V1 request
#   nc_request=$(cat <<EOF
# {
#   "ReservationID": "$RESERVATION_ID",
#   "ReservationSetID": "$RESERVATION_SET_ID",
#   "AssociationInfo": {
#     "NodeID": "$NODE_ID",
#     "InterfaceID": "$IFACE_ID",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
# )
# fi

# echo "NC request payload: $nc_request"

#   # Send the POST request to create the NC
#   response=$(curl -s -w "%{http_code}" -o /tmp/create_nc_response.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID?api-version=2018-03-01" \
#     -H "Content-Type: application/json" \
#     -d "$nc_request")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful or if there was a conflict
#   if [[ "$http_status" -ne 200 && "$http_status" -ne 409 ]]; then
#     echo "Failed to create NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/create_nc_response.json
#     return 1
#   fi

#   echo "Successfully created NC: $NC_ID"
#   cat /tmp/create_nc_response.json
# }

# # Function to poll the NC status
# poll_nc_status() {
#   echo "Polling status of NC: $NC_ID"

#   # Send the GET request to check the NC status
#   response=$(curl -s -w "%{http_code}" -o /tmp/nc_status_response.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID/status?api-version=2018-03-01" \
#     -H "Content-Type: application/json")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to get status for NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/nc_status_response.json
#     return 1
#   fi

#   # Parse the status from the response
#   nc_status=$(jq -r '.Status' /tmp/nc_status_response.json)
#   if [[ "$nc_status" != "Completed" ]]; then
#     echo "NC $NC_ID status is not 'Completed'. Current status: $nc_status"
#     return 1
#   fi

#   echo "NC $NC_ID status is 'Completed'."
# }

# attempt=1
# while [[ $attempt -le $RETRY_COUNT ]]; do
#   if create_nc; then
#     echo "Create NC succeeded on attempt $attempt."
#     break
#   fi

#   echo "Create NC failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
#   sleep "$RETRY_DELAY"
#   attempt=$((attempt + 1))
# done

# if [[ $attempt -gt $RETRY_COUNT ]]; then
#   echo "Failed to create NC after $RETRY_COUNT attempts."
#   exit 1
# fi

# # Retry logic for polling the NC status
# attempt=1
# while [[ $attempt -le $RETRY_COUNT ]]; do
#   if poll_nc_status; then
#     echo "NC status check succeeded on attempt $attempt."
#     exit 0
#   fi

#   echo "NC status check failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
#   sleep "$RETRY_DELAY"
#   attempt=$((attempt + 1))
# done

# echo "Failed to verify NC status after $RETRY_COUNT attempts."


########################### new code  ###########################
# NODES=(
#   "linuxpool160000000|10.224.0.76|container1-pod"  # Format: NODE_NAME|NODE_IP|POD_NAME
#   "linuxpool161000000|10.224.0.78|container2-pod"
# )

# DNC_API_ENDPOINT=$DNC_URL  # Replace with the actual DNC endpoint
# CUSTOMER_VNET_GUID="3f84330f-6410-4996-bb28-78513d2eb093"  # Replace with your customer VNet GUID
# CUSTOMER_SUBNET_NAME="delegatedSubnet"
# POD_NAMESPACE="default"  # Replace with the pod namespace
# RETRY_COUNT=20  # Number of retry attempts
# RETRY_DELAY=3  # Delay between retries in seconds
# IP_CONSTRAINT=""
# NODE_CONSTRAINT=""
# SECONDARY_IP_COUNT=0
# PRIMARY_IP_PREFIX_BITS=0
# CONTAINER_TYPE="AzureContainerInstance"
# OWNER_ID=""
# RESERVATION_ID=""
# RESERVATION_SET_ID=""
# HOST_TO_NC=false
# NC_TO_HOST=false

# # Function to create a network container (NC)
# create_nc() {
#   local NODE_NAME=$1
#   local NODE_IP=$2
#   local POD_NAME=$3
#   local NC_ID=$(uuidgen)  # Generate a unique NC ID

#   echo "Attempting to create NC: $NC_ID on node: $NODE_NAME with pod: $POD_NAME"

#   # Construct the NC request payload
#   if [[ -z "$RESERVATION_ID" && -z "$RESERVATION_SET_ID" ]]; then
#     # V2 request
#     nc_request=$(cat <<EOF
# {
#   "AllocationRequest": {
#     "SubnetName": "$CUSTOMER_SUBNET_NAME",
#     "IPConstraint": "$IP_CONSTRAINT",
#     "NodeConstraint": "$NODE_CONSTRAINT",
#     "SecondaryIPCount": $SECONDARY_IP_COUNT,
#     "PrimaryIPPrefixBits": $PRIMARY_IP_PREFIX_BITS
#   },
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$NODE_IP",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
#     )
#   else
#     # V1 request
#     nc_request=$(cat <<EOF
# {
#   "ReservationID": "$RESERVATION_ID",
#   "ReservationSetID": "$RESERVATION_SET_ID",
#   "AssociationInfo": {
#     "NodeID": "$NODE_NAME",
#     "InterfaceID": "$NODE_IP",
#     "ContainerType": "$CONTAINER_TYPE",
#     "OrchestratorContext": {
#       "PodName": "$POD_NAME",
#       "PodNamespace": "$POD_NAMESPACE"
#     }
#   },
#   "AllowHostToNCCommunication": $HOST_TO_NC,
#   "AllowNCToHostCommunication": $NC_TO_HOST,
#   "OwnerID": "$OWNER_ID"
# }
# EOF
#     )
#   fi

#   echo "NC request payload: $nc_request"

#   # Send the POST request to create the NC
#   response=$(curl -s -w "%{http_code}" -o /tmp/create_nc_response_$NC_ID.json -X POST "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID?api-version=2018-03-01" \
#     -H "Content-Type: application/json" \
#     -d "$nc_request")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful or if there was a conflict
#   if [[ "$http_status" -ne 200 && "$http_status" -ne 409 ]]; then
#     echo "Failed to create NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/create_nc_response_$NC_ID.json
#     return 1
#   fi

#   echo "Successfully created NC: $NC_ID"
#   cat /tmp/create_nc_response_$NC_ID.json
# }

# # Function to poll the NC status
# poll_nc_status() {
#   local NC_ID=$1

#   echo "Polling status of NC: $NC_ID"

#   # Send the GET request to check the NC status
#   response=$(curl -s -w "%{http_code}" -o /tmp/nc_status_response_$NC_ID.json -X GET "$DNC_API_ENDPOINT/networks/$CUSTOMER_VNET_GUID/networkcontainer/$NC_ID/status?api-version=2018-03-01" \
#     -H "Content-Type: application/json")

#   # Extract HTTP status code
#   http_status=$(tail -n1 <<< "$response")

#   # Check if the request was successful
#   if [[ "$http_status" -ne 200 ]]; then
#     echo "Failed to get status for NC $NC_ID. HTTP status: $http_status"
#     cat /tmp/nc_status_response_$NC_ID.json
#     return 1
#   fi

#   # Parse the status from the response
#   nc_status=$(jq -r '.Status' /tmp/nc_status_response_$NC_ID.json)
#   if [[ "$nc_status" != "Completed" ]]; then
#     echo "NC $NC_ID status is not 'Completed'. Current status: $nc_status"
#     return 1
#   fi

#   echo "NC $NC_ID status is 'Completed'."
# }

# # Iterate over the nodes and register NCs for each
# for node in "${NODES[@]}"; do
#   IFS="|" read -r NODE_NAME NODE_IP POD_NAME <<< "$node"

#   # Retry logic for creating the NC
#   attempt=1
#   while [[ $attempt -le $RETRY_COUNT ]]; do
#     if create_nc "$NODE_NAME" "$NODE_IP" "$POD_NAME"; then
#       echo "Create NC succeeded on attempt $attempt for node: $NODE_NAME."
#       break
#     fi

#     echo "Create NC failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
#     sleep "$RETRY_DELAY"
#     attempt=$((attempt + 1))
#   done

#   if [[ $attempt -gt $RETRY_COUNT ]]; then
#     echo "Failed to create NC for node: $NODE_NAME after $RETRY_COUNT attempts."
#     exit 1
#   fi

#   # Retry logic for polling the NC status
#   attempt=1
#   while [[ $attempt -le $RETRY_COUNT ]]; do
#     if poll_nc_status "$NC_ID"; then
#       echo "NC status check succeeded on attempt $attempt for node: $NODE_NAME."
#       break
#     fi

#     echo "NC status check failed on attempt $attempt for node: $NODE_NAME. Retrying in $RETRY_DELAY seconds..."
#     sleep "$RETRY_DELAY"
#     attempt=$((attempt + 1))
#   done

#   if [[ $attempt -gt $RETRY_COUNT ]]; then
#     echo "Failed to verify NC status for node: $NODE_NAME after $RETRY_COUNT attempts."
#     exit 1
#   fi
# done

# echo "All NCs registered and verified successfully!"



############################ Deploy Pods ###########################
# POD_NAME="container1-pod"
# NODE_NAME="linuxpool161000000"
# POD_YAML="container1.yaml"
# LABEL_SELECTOR="cx=vm1"

# POD_NAME="container1-pod"
# NODE_NAME="linuxpool163000000"
# POD_YAML="container1.yaml"
# LABEL_SELECTOR="cx=vm1"

# NAMESPACE="default"  # Replace with the namespace of the DNC deployment
# POD_HEALTH_CHECK_RETRY_COUNT=10  # Number of retry attempts
# POD_HEALTH_CHECK_RETRY_DELAY=5  # Delay between retries in seconds

# # Function to deploy pods
# deploy_pods() {
#   kubectl label node $NODE_NAME $LABEL_SELECTOR --overwrite
#   kubectl apply -f "$POD_YAML" -n "$NAMESPACE"
#   echo "Pod $POD_NAME deployed successfully"
# }

# # Function to check pod health
# check_pod_health() {
#   echo "Checking pod health..."
#   for ((attempt = 1; attempt <= $POD_HEALTH_CHECK_RETRY_COUNT; attempt++)); do
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

# # Example: Deploy pods for the nodes
# echo "Deploying pods for nodes..."
# deploy_pods

# # Check pod health
# echo "Checking pod health..."
# check_pod_health

# echo "Orchestration completed successfully."

############# new code for orchestrating pods #############
# Define an array of pods with their details
# PODS=(
#   "container2-pod|linuxpool162000000|container2.yaml|cx=vm2"  # Format: POD_NAME|NODE_NAME|POD_YAML|LABEL_SELECTOR
#   "container1-pod|linuxpool163000000|container1.yaml|cx=vm1"
# )

# NAMESPACE="default"  # Replace with the namespace of the DNC deployment
# POD_HEALTH_CHECK_RETRY_COUNT=10  # Number of retry attempts
# POD_HEALTH_CHECK_RETRY_DELAY=5  # Delay between retries in seconds

# # Function to deploy a pod
# deploy_pod() {
#   local POD_NAME=$1
#   local NODE_NAME=$2
#   local POD_YAML=$3
#   local LABEL_SELECTOR=$4

#   echo "Deploying pod: $POD_NAME on node: $NODE_NAME with YAML: $POD_YAML"

#   # Label the node
#   kubectl label node "$NODE_NAME" "$LABEL_SELECTOR" --overwrite

#   # Apply the pod YAML
#   kubectl apply -f "$POD_YAML" -n "$NAMESPACE"

#   echo "Pod $POD_NAME deployed"
# }

# # Function to check pod health
# check_pod_health() {
#   local POD_NAME=$1
#   local LABEL_SELECTOR=$2

#   echo "Checking health for pod: $POD_NAME..."
#   for ((attempt = 1; attempt <= $POD_HEALTH_CHECK_RETRY_COUNT; attempt++)); do
#     pod_list=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json)
#     pod_count=$(echo "$pod_list" | jq '.items | length')

#     if [[ "$pod_count" -eq 0 ]]; then
#       echo "No pods scheduled for $POD_NAME. Retrying in $POD_HEALTH_CHECK_RETRY_DELAY seconds..."
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
#       echo "Pod $POD_NAME is healthy and running."
#       return 0
#     fi

#     echo "Pod $POD_NAME is not ready. Retrying in $POD_HEALTH_CHECK_RETRY_DELAY seconds..."
#     sleep "$POD_HEALTH_CHECK_RETRY_DELAY"
#   done

#   echo "Failed to verify health for pod $POD_NAME after $POD_HEALTH_CHECK_RETRY_COUNT attempts."
#   exit 1
# }

# # Main script logic
# echo "Starting orchestration..."

# # Iterate over the pods and deploy each one
# for pod in "${PODS[@]}"; do
#   IFS="|" read -r POD_NAME NODE_NAME POD_YAML LABEL_SELECTOR <<< "$pod"

#   # Deploy the pod
#   deploy_pod "$POD_NAME" "$NODE_NAME" "$POD_YAML" "$LABEL_SELECTOR"

#   # Check the pod's health
#   # check_pod_health "$POD_NAME" "$LABEL_SELECTOR"
# done

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