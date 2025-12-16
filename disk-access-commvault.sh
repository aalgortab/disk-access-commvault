#!/bin/bash

# --- Configuration ---
# Set to "true" for a dry run (show changes without applying), "false" to apply changes.

subscriptionId="xxxx-xxxxx-xxxxx"

az account set --subscription "$subscriptionId"

DRY_RUN="false"

# Resource ID of your Disk Access resource
DISK_ACCESS_ID="/subscriptions/xxxx-xxxx-xxxx/resourceGroups/rsg/providers/Microsoft.Compute/diskAccesses/diskaccess"

# List of VM names whose disks should be processed
# List of VM names whose disks should be processed
declare -a VM_NAMES=(
    "vm1"
    "vm3"
    "vm3"
)

# --- Script Logic ---

echo "--- Azure Disk Access Management Script ---"

if [ "$DRY_RUN" = "true" ]; then
    echo "DRY RUN MODE: No changes will be applied to your Azure resources."
    echo "This script will ONLY report what it WOULD do."
else
    echo "LIVE RUN MODE: Changes WILL BE APPLIED to your Azure resources."
    read -p "Are you sure you want to proceed? (yes/no) " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi
fi
echo ""

echo "Processing disks for specified VMs..."

# Loop through each VM name
for VM_NAME in "${VM_NAMES[@]}"; do
    echo "----------------------------------------------------"
    echo "Checking VM: $VM_NAME"

    VM_INFO=$(az vm list --query "[?name=='$VM_NAME'].{id:id, resourceGroup:resourceGroup}" -o json 2>/dev/null)

    if [ -z "$VM_INFO" ] || [ "$VM_INFO" == "[]" ]; then
        echo "  WARNING: VM '$VM_NAME' not found in the current subscription or no access. Skipping."
        echo "----------------------------------------------------"
        continue
    fi

    VM_ID=$(echo "$VM_INFO" | jq -r '.[0].id')
    VM_RESOURCE_GROUP=$(echo "$VM_INFO" | jq -r '.[0].resourceGroup')

    if [ "$VM_ID" == "null" ] || [ "$VM_RESOURCE_GROUP" == "null" ]; then
         echo "  WARNING: Could not parse VM ID or Resource Group for VM '$VM_NAME'. Skipping."
         echo "----------------------------------------------------"
         continue
    fi

    echo "  Found VM '$VM_NAME' in Resource Group: '$VM_RESOURCE_GROUP'"

    # Get OS disk ID
    OS_DISK_ID=$(az vm show --ids "$VM_ID" --query "storageProfile.osDisk.managedDisk.id" -o tsv 2>/dev/null)
    # Get Data disk IDs
    DATA_DISK_IDS=$(az vm show --ids "$VM_ID" --query "storageProfile.dataDisks[].managedDisk.id" -o tsv 2>/dev/null)

    ALL_DISK_IDS=()
    if [ -n "$OS_DISK_ID" ]; then
        ALL_DISK_IDS+=("$OS_DISK_ID")
    fi
    if [ -n "$DATA_DISK_IDS" ]; then
        while IFS= read -r line; do
            ALL_DISK_IDS+=("$line")
        done <<< "$DATA_DISK_IDS"
    fi

    if [ ${#ALL_DISK_IDS[@]} -eq 0 ]; then
        echo "  No managed disks found for VM '$VM_NAME'. Skipping."
        echo "----------------------------------------------------"
        continue
    fi

    echo "  Found ${#ALL_DISK_IDS[@]} managed disks for '$VM_NAME'."

    # Process each disk found for the current VM
    for DISK_ID in "${ALL_DISK_IDS[@]}"; do
        echo "    Processing disk: $DISK_ID"

        DISK_RESOURCE_GROUP=$(echo "$DISK_ID" | cut -d'/' -f5)
        DISK_NAME=$(echo "$DISK_ID" | cut -d'/' -f9)

        echo "      Disk Name: $DISK_NAME (in RG: $DISK_RESOURCE_GROUP)"

        # Get the actual network access properties for more precise checking
        DISK_NETWORK_STATUS=$(az disk show --ids "$DISK_ID" --query "{publicNetworkAccess:publicNetworkAccess, diskAccessId:diskAccessId}" -o json 2>/dev/null)

        PUBLIC_ACCESS=$(echo "$DISK_NETWORK_STATUS" | jq -r '.publicNetworkAccess')
        PRIVATE_ACCESS_ID=$(echo "$DISK_NETWORK_STATUS" | jq -r '.diskAccessId')

        echo "      Detected Public Network Access: '$PUBLIC_ACCESS'"
        echo "      Detected Private Access ID: '$PRIVATE_ACCESS_ID'"

        SHOULD_UPDATE="false"

        # **CRITICAL CHANGE: ONLY target disks that are "Completely isolated"**
        # This means publicNetworkAccess is 'Disabled' AND diskAccessId is 'null'
        if [[ "$PUBLIC_ACCESS" == "Disabled" && "$PRIVATE_ACCESS_ID" == "null" ]]; then
            echo "      Disk is currently 'Disable public and private access' (completely isolated). This disk will be targeted for update."
            SHOULD_UPDATE="true"
        else
            echo "      Disk is NOT 'Disable public and private access' (either public or already private). Skipping this disk as per requirement."
            SHOULD_UPDATE="false"
        fi

        if [ "$SHOULD_UPDATE" = "true" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo "      DRY RUN: Would change network access policy to 'AllowPrivate' and attach disk access '$DISK_ACCESS_ID'."
                echo "      DRY RUN Command: az disk update --resource-group \"$DISK_RESOURCE_GROUP\" --name \"$DISK_NAME\" --network-access-policy AllowPrivate --disk-access \"$DISK_ACCESS_ID\""
            else
                echo "      Applying changes: Changing to 'Disable public access and enable private access'..."
                az disk update \
                    --resource-group "$DISK_RESOURCE_GROUP" \
                    --name "$DISK_NAME" \
                    --network-access-policy AllowPrivate \
                    --disk-access "$DISK_ACCESS_ID" \
                    --output none
                if [ $? -eq 0 ]; then
                    echo "      SUCCESS: Disk '$DISK_NAME' updated to 'AllowPrivate' and Disk Access attached."
                else
                    echo "      FAILURE: Could not update disk '$DISK_NAME'. Please check logs for details."
                # Optionally, if you want to explicitly detach existing DiskAccessId before reattaching a new one,
                # you'd add logic here, but for this specific "completely isolated" target, it's not needed.
                fi
            fi
        fi
        echo ""
    done
    echo "----------------------------------------------------"
done

echo "--- Script complete ---"
