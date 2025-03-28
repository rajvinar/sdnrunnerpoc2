#!/bin/bash

# For consistency sake install the Azure CA certificates on the node
# regardless of whether or not we are in the AGC

echo "INSTALLING AZURE CA CERTIFICATES..."
sudo mkdir -p /root/AzureCACertificates
# http://168.63.129.16 is a constant for the host's wireserver endpoint
certs=$(curl "http://168.63.129.16/machine?comp=acmspackage&type=cacertificates&ext=json")
if [ -z "$certs" ]; then
    echo "Failed to retrieve certificates from the wireserver endpoint."
    exit 1
fi
IFS=$'\r\n'
certNames=($(echo $certs | grep -oP '(?<=Name\": \")[^\"]*'))
certBodies=($(echo $certs | grep -oP '(?<=CertBody\": \")[^\"]*'))
for i in ${!certBodies[@]}; do
    # This line adds the cert to /root/AzureCACertificates and replaces the .cer or missing file extension with the .crt extension.
    # It also replaces any Windows line endings with Unix ones.
    echo ${certBodies[$i]} | sed 's/\\r\\n/\n/g' | sed 's/\\//g' > "/root/AzureCACertificates/$(echo ${certNames[$i]} | sed 's/.cer/.crt/g' | sed 's/\.[^.]*$/.crt&/;t;s/$/.crt/')"
done
IFS=$IFS_backup
sudo cp /root/AzureCACertificates/*.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
echo "AZURE CA CERTIFICATES INSTALLED."