param hubsub string
param hubgroup string
param extversion string = ''
param msiRg string = 'RunnersIdentities'
import * as cloud from 'clouds.bicep'
var artifactHostname = cloud.GetArtifactHostName(tenant().tenantId)
var artifactUrl = cloud.GetArtifactUrl(tenant().tenantId)
var mcrUrl = cloud.GetMcrHostname(tenant().tenantId)
var runcVersion = cloud.GetRuncVersion(tenant().tenantId)
var containerdVersion = cloud.GetContainerdVersion(tenant().tenantId)
var kubeLoginVersion = cloud.GetKubeLoginVersion(tenant().tenantId)

resource aks 'Microsoft.ContainerService/managedClusters@2023-06-01' existing = {
  name: 'aks'
  scope: resourceGroup(hubsub, hubgroup)
}

resource aksbootstrapid 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  // name: 'helm-script-msi3'
  // scope: resourceGroup(hubsub, hubgroup)
  scope: resourceGroup(hubsub, msiRg)
  name: 'deploymentscript-msi'
}

var kubeconfig = base64ToString(aks.listClusterUserCredential().kubeconfigs[0].value)

var currentVersion = aks.properties.kubernetesVersion
var currentVersionArray = split(currentVersion, '.')
var kubeletversion = cloud.GetK8sVersion(currentVersionArray, tenant().tenantId)

var fqdn = aks.properties.fqdn
var cert = split(substring(kubeconfig, indexOf(kubeconfig, 'certificate-authority-data: ') + 28), '\n')[0]

var delayextandwaitdnsready = 'echo ${loadFileAsBase64('./delayext-and-waitdnsready.sh')} | base64 -d | bash -s ${fqdn} ${artifactHostname}'
var cacertscript = 'echo ${loadFileAsBase64('./cacert.sh')} | base64 -d | bash -s '
var configscript = 'echo ${loadFileAsBase64('./config.sh')} | base64 -d | bash -s'
var containerdscript = 'echo ${loadFileAsBase64('./containerd.sh')} | base64 -d | bash -s ${artifactUrl} ${runcVersion} ${containerdVersion} ${mcrUrl}'
var kubeletmsiscript = 'echo ${loadFileAsBase64('./kubelet-msi.sh')} | base64 -d | bash -s ${fqdn} ${aksbootstrapid.properties.clientId} ${artifactUrl} ${kubeLoginVersion}'
var kubeletscript = 'echo ${loadFileAsBase64('./kubelet.sh')} | base64 -d | bash -s ${kubeletversion} ${fqdn} ${cert} ${artifactUrl}'

var defaultScripts = [
  delayextandwaitdnsready
  cacertscript
  '${configscript} false false'
  '${containerdscript} runc'
  kubeletmsiscript
]

var bootstrapscripts = {
  Standard_E16s_v3: concat(defaultScripts, ['${kubeletscript} Standard_E16s_v3 redis'])
  Standard_E8s_v3: concat(defaultScripts, ['${kubeletscript} Standard_E8s_v3 cpu'])
  Standard_D8s_v3: concat(defaultScripts, ['${kubeletscript} Standard_D8s_v3 cpu'])
  Standard_D16s_v3: concat(defaultScripts, ['${kubeletscript} Standard_D16s_v3 cpu'])
  Standard_D32s_v3: concat(defaultScripts, ['${kubeletscript} Standard_D32s_v3 cpu'])
  Standard_D48s_v3: concat(defaultScripts, ['${kubeletscript} Standard_D48s_v3 cpu'])
  Standard_D64s_v3: concat(defaultScripts, ['${kubeletscript} Standard_D64s_v3 cpu'])
}

output scripts object = reduce(map(items(bootstrapscripts), (entity) => {
  key: entity.key
  val: base64(join(concat([
    '#!/bin/bash'
    'set -ex'
    '[[ -f "/var/lib/kubelet/kubeconfig" ]] && echo "please reimage to trigger newer kube ext" && exit 0'
    'echo NEXUS: ${extversion}, HASH ${uniqueString(join(entity.value, '\n'))}'
  ], entity.value, [
    'shutdown -r +1'
    'echo ${extversion} > /etc/nexus-kube-version'
  ]), '\n'))
}), {}, (cur, next) => union(cur,  {'${next.key}': next.val} ))
