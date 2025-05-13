@export()
func GetCannonicalUbuntuImageOffer(tenantId string) string =>  GetCannonicalUbuntuImageSku(tenantId) == '22_04-lts-gen2' ? '0001-com-ubuntu-server-jammy' : 'unknown-sku'

@export()
func GetCannonicalUbuntuImageSku(tenantId string) string => '22_04-lts-gen2'

@export()
func GetMcrHostname(tenantId string) string => 'mcr.microsoft.com'

@export()
func GetK8sVersion(currentVersionArray string[], tenantId string) string => '1.30.4'

@export()
func GetRuncVersion(tenantId string) string => '1.1.12'

@export()
func GetContainerdVersion(tenantId string) string => '1.7.15'

@export()
func GetKubeLoginVersion(tenantId string) string => '0.0.31'

@export()
func GetArtifactHostName(tenantId string) string => 'nexusstaticsa.blob.${GetStorageAccountSuffix()}'

@export()
func GetArtifactUrl(tenantId string) string => 'https://${GetArtifactHostName(tenantId)}'

@export()
func GetStorageAccountSuffix() string => startsWith(environment().suffixes.storage, '.') ?  skip(environment().suffixes.storage, 1) : environment().suffixes.storage