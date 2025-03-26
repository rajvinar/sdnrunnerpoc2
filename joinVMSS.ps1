param ([string]$ResourceGroup, [string]$ClusterName, [string]$BicepTemplatePath, [string]$AdminPassword, [string]$VnetName, [string]$SubnetName, [string]$SubscriptionId)

# Set the subscription
Write-Host "Setting the subscription to $SubscriptionId..."
az account set --subscription $SubscriptionId

# Retrieve the Object ID of the managed identity
Write-Host "Retrieving Object ID of the managed identity..."
$Oid = az identity show --ids "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/helm-script-msi" --query principalId -o tsv
Write-Host "OID: $Oid"

# Authenticate with the AKS cluster
Write-Host "Authenticating with AKS cluster..."
$KubeConfigPath = Join-Path (Get-Location) "kubeconfig.yaml"
$null = az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing -a
Write-Host "Successfully authenticated with AKS cluster."

# Apply the Kubernetes role using the managed identity
Write-Host "Applying Kubernetes role for the managed identity..."
(Get-Content "bootstrap-role.yaml") -replace "__OBJECT_ID__", $Oid | Set-Content "bootstrap-role.yaml"

# # Define VMSS names
# $VmssNames = @("dncpool1", "linuxpool1")

# # Loop through VMSS names and create VMSS
# foreach ($VmssName in $VmssNames) {
#     $ExtensionName = "NodeJoin-$VmssName"
#     Write-Host "Creating VMSS: $VmssName with extension: $ExtensionName"

#     Start-Process -NoNewWindow -FilePath "az" -ArgumentList @(
#         "deployment group create",
#         "--name vmss-deployment-$VmssName",
#         "--resource-group $ResourceGroup",
#         "--template-file $BicepTemplatePath",
#         "--parameters",
#         "vnetname=$VnetName",
#         "subnetname=$SubnetName",
#         "name=$VmssName",
#         "adminPassword=$AdminPassword",
#         "vnetrgname=$ResourceGroup",
#         "extensionName=$ExtensionName"
#     ) -RedirectStandardOutput "./lin-script-$VmssName.log" -RedirectStandardError "./lin-script-$VmssName.log" -Wait
# }

# # Display logs for each VMSS deployment
# foreach ($VmssName in $VmssNames) {
#     Write-Host "Displaying logs for $VmssName deployment:"
#     Get-Content "./lin-script-$VmssName.log"
# }

# Define VMSS names
$VmssNames = @("dncpool1", "linuxpool1")

# Loop through VMSS names and create VMSS
foreach ($VmssName in $VmssNames) {
    $ExtensionName = "NodeJoin-$VmssName"
    Write-Host "Creating VMSS: $VmssName with extension: $ExtensionName"

    az deployment group create `
        --name "vmss-deployment-$VmssName" `
        --resource-group "$ResourceGroup" `
        --template-file "$BicepTemplatePath" `
        --parameters `
        vnetname="$VnetName" `
        subnetname="$SubnetName" `
        name="$VmssName" `
        adminPassword="$AdminPassword" `
        vnetrgname="$ResourceGroup" `
        extensionName="$ExtensionName"
}

Write-Host "VMSS creation completed."


# Verify the nodes are ready
Write-Host "Verifying that nodes are ready..."
$Nodes = kubectl get nodes -l kubernetes.azure.com/managed=false -o jsonpath='{.items[*].metadata.name}'
foreach ($Node in $Nodes) {
    $Ready = kubectl get node $Node -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
    if ($Ready -ne "True") {
        Write-Error "Node $Node is not ready. Exiting."
        exit 1
    }
}
Write-Host "All nodes are ready and joined to the AKS cluster."

# Promote one of the VMSS to be a system pool
$SystemPoolName = "dncpool1"
Write-Host "Promoting VMSS $SystemPoolName to be a system pool..."
az aks nodepool update --cluster-name $ClusterName --resource-group $ResourceGroup --name $SystemPoolName --mode System
Write-Host "VMSS $SystemPoolName has been promoted to a system pool."

# Delete old node pools
$NodePoolsToDelete = @("dncpool0", "linuxpool0")
foreach ($NodePool in $NodePoolsToDelete) {
    Write-Host "Deleting node pool: $NodePool from AKS cluster: $ClusterName in resource group: $ResourceGroup..."
    az aks nodepool delete --resource-group $ResourceGroup --cluster-name $ClusterName --name $NodePool --yes
    Write-Host "Node pool $NodePool deleted successfully."
}

# Verify the remaining node pools
Write-Host "Remaining node pools in the cluster:"
az aks nodepool list --resource-group $ResourceGroup --cluster-name $ClusterName -o table