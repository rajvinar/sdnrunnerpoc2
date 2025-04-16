echo "auth to aks..."
az aks get-credentials --resource-group dala-aks-runner7 --name aks --overwrite-existing  --admin || exit 1

NAMESPACE="default"  # Replace with the namespace of the DNC deployment
LABEL_SELECTOR="app=dnc"  # Replace with the label selector for the DNC pod
LOCAL_PORT=9000  # Local port to forward
REMOTE_PORT=9000  # Pod's port to forward
DNC_POD="dnc-7b76546bfd-kcc4d"

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
# NODE_ID="dncpool12000000"                 # Replace with the actual Node ID
# NODE_API="$DNC_ENDPOINT/nodes/$NODE_ID?api-version=2018-03-01"
# JSON_CONTENT_TYPE="application/json"

# # Node information payload
# NODE_INFO_JSON=$(cat <<EOF
# {
#   "IPAddresses": ["10.224.0.69"],
#   "OrchestratorType": "Kubernetes",
#   "InfrastructureNetwork": "cd28d33f-1589-44d3-98a4-7cc84d03d6d4",
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
DNC_ENDPOINT=$DNC_URL #"https://10.224.0.65:9000"  # Replace with the actual DNC endpoint
NETWORK_ID="10177921-2ed7-464c-be21-661407a1e10f"  # Replace with your network ID
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
    echo "Failed to add network $network_id. HTTP status: $http_status"
    cat /tmp/add_network_response.json
    exit 1
  fi

  echo "Successfully added network $network_id."
  cat /tmp/add_network_response.json


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