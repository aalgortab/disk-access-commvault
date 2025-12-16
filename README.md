# Azure Disk Access Remediation Script

## Overview
This Bash script automates the remediation of Azure Managed Disks that are causing backup failures in Commvault (and other backup solutions requiring SAS tokens). 

Specifically, it addresses the `PublicNetworkAccessDisabled` error by identifying disks that are in a state of **Total Isolation** (Public Access Disabled + No Private Access) and transitioning them to **Private Access** by attaching a specific Azure Disk Access resource.

## The Problem
Azure Managed Disks have three network states:
1. **Public Access:** Enabled.
2. **Private Access:** Public disabled, but linked to a Disk Access resource.
3. **Total Isolation:** Public disabled, no Disk Access resource linked.

Commvault snapshots fail when disks are in state #3 because Azure cannot generate a valid SAS token for data transfer. This script moves disks from state #3 to state #2.

## Features
* **Targeted Scope:** Only processes disks attached to a specific list of VMs.
* **Smart Filtering:** Automatically detects and skips disks that are already configured correctly or are public. It **only** targets disks that are completely isolated.
* **Dry Run Mode:** Includes a safety switch (`DRY_RUN="true"`) to preview intended changes without modifying resources.
* **Bulk Processing:** Handles both OS and Data disks for multiple VMs in a single execution.
* **Azure CLI Native:** Relies on standard `az` commands and `jq` for JSON parsing.

## Prerequisites
* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (`az login`).
* `jq` installed (JSON processor).
* Contributor permissions on the target VMs and the Disk Access resource.

## Configuration
Open the script and update the following variables at the top of the file:

1.  **`DISK_ACCESS_ID`**: The Resource ID of your Disk Access resource (e.g., `/subscriptions/.../diskAccesses/disk-access-prod`).
2.  **`VM_NAMES`**: The array of VM names you wish to remediate.

```bash
declare -a VM_NAMES=(
    "VM-Name-01"
    "VM-Name-02"
)
