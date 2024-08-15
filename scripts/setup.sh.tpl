#!/bin/bash

apikey="${ibmcloud_api_key}"
apikey_id="${ibmcloud_api_key_id}"
cos_bucket_name="${cos_bucket_name}"
region="${vpc_region}"
cos_region="${cos_region}"
nfs_mount_string="${nfs_mount_string}"
aspera_dl_dir="${export_volume_directory}"
private_network_cidr="${vpc_subnet_cidr}"
download_dir=/tmp
aspera_part_label=aspera-data
cos_endpoint="https://s3.direct.$cos_region.cloud-object-storage.appdomain.cloud/"

# Wait for network
until ping -c1 ibm-cloud-cli-installer-scripts.s3.direct.us.cloud-object-storage.appdomain.cloud >/dev/null 2>&1; do :; done
echo "Network found"

# Install IBM Cloud CLI
curl -fsSL https://ibm-cloud-cli-installer-scripts.s3.direct.us.cloud-object-storage.appdomain.cloud/linux_vpc | sh

# Login to IBM Cloud
export IBMCLOUD_API_KEY=$apikey
ibmcloud login -r us-south -a https://private.cloud.ibm.com
oauth_token=`ibmcloud iam oauth-tokens | awk '{print $4}'`

# Get COS bucket metadata
cos_bucket_xml=`curl "$cos_endpoint/$cos_bucket_name" --header "Authorization: Bearer $oauth_token"`

read_dom () {
    local IFS=\>
    read -d \< KEY VALUE
}

aspera_license_filename=""
aspera_installer_filename=""
aspera_installer_pattern="^ibm-aspera-(.*)-linux-64-release.rpm$"
while read_dom; do
    if [[ $KEY = "Key" ]]; then
        if [[ $aspera_license_filename ]] && [[ $aspera_installer_filename ]]; then
            echo "Aspera license and installer successfully downloaded"
            break
        fi

        if [[ $VALUE == *".aspera-license" ]]; then
            aspera_license_filename="$VALUE"
            curl -o "$download_dir/$aspera_license_filename" "$cos_endpoint/$cos_bucket_name/$aspera_license_filename" --header "Authorization: Bearer $oauth_token"
            if [[ $? -ne 0 ]]; then
                echo "Failed to download Aspera license: $aspera_license_filename"
                exit 1
            fi
            continue
        fi

        if [[ $VALUE =~ $aspera_installer_pattern ]]; then
            aspera_installer_filename="$VALUE"
            curl -o "$download_dir/$aspera_installer_filename" "$cos_endpoint/$cos_bucket_name/$aspera_installer_filename" --header "Authorization: Bearer $oauth_token"
            if [[ $? -ne 0 ]]; then
                echo "Failed to download Aspera installer: $aspera_installer_filename"
                exit 1
            fi
            continue
        fi
    fi
done <<< "$cos_bucket_xml"

if [[ -z $aspera_installer_filename ]] || [[ -z $aspera_license_filename ]]; then
    echo "Aspera download failed"; exit 1
fi
echo "Aspera successfully downloaded"

# Mount Aspera Destination
mkdir -p $aspera_dl_dir
if [[ -z "$nfs_mount_string" ]]; then
    echo "Using block storage"
    # Look for existing aspera partition
    storage_part=$(find -L /dev/v* -samefile /dev/disk/by-label/$aspera_part_label 2> /dev/null)
    if [[ -z "$storage_part" ]]; then
        echo Initialize block storage

        # Find the boot device
        efi_part=$(find -L /dev/v* -samefile /dev/disk/by-label/EFI)
        efi_parts=($${efi_part//\// })
        efi_dev=$${efi_parts[1]::-1}
        echo "Boot device: $efi_dev"

        # Find the new storage device
        storage_id=$(stat -c%N /dev/disk/by-id/virtio* | grep -v -e "$efi_dev" -e "cloud" -e "part" | awk '{print $1}' | tr -d "'")
        storage_dev=$(find -L /dev/v* -samefile "$storage_id" 2> /dev/null)
        storage_part=$${storage_dev}1
        echo "Block storage: $storage_dev"

        # Partition local storage
        echo 'type=83' | sfdisk $storage_dev
        mkfs.ext4 $storage_part
        e2label $storage_part $aspera_part_label
    fi

    # Mount local storage
    echo "Mount Aspera storage $storage_part @ $aspera_dl_dir"
    echo "$storage_part $aspera_dl_dir ext4 defaults 0 2" >> /etc/fstab
    mount -a

    # Export local storage
    echo "Enable Aspera NFS share: $aspera_dl_dir"
    chmod 777 $aspera_dl_dir
    systemctl enable --now nfs-server.service rpcbind.service
    echo "$aspera_dl_dir $${private_network_cidr}(rw,sync,no_subtree_check)" >> /etc/exports
    exportfs -ra
else
    # Mount remote storage
    echo "Using NFS storage"
    echo "Mount Aspera storage $nfs_mount_string @ $aspera_dl_dir"
    echo "$nfs_mount_string $aspera_dl_dir nfs defaults 0 0" >> /etc/fstab
    mount -a
fi

# Install Aspera
echo "Install Aspera..."
rpm -ivh $download_dir/$aspera_installer_filename
mv $download_dir/$aspera_license_filename /opt/aspera/etc/aspera-license
asconfigurator -F "set_user_data;user_name,root;absolute,$aspera_dl_dir"
ascp -A

# Delete API key
# TODO: Use Trusted Profiles
echo "Remove temporary API key"
ibmcloud iam api-key-delete -f $apikey_id

# Remove this file
echo "Cleanup"
rm $0

echo "Done"
