#!/usr/bin/env bash

# ==============================================================================
# Script Name : deploy_real_time-metrics.sh
# Description : Triggers the deployment of the Real Time Metrics component.
# Author      : Gary Blake
# Usage       : ./deploy_real_time-metrics.sh [log directory]
# ==============================================================================

# 1. Shell Options & Error Handling
set -euo pipefail

# 2. Environment & Global Variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_DIR="${1:-../log/audit}"
readonly VCF_FLEET_LIFECYCLE_FQDN="${2:-flt-fc01.rainpole.io}"
readonly VCF_FLEET_LIFECYCLE_USER="${3:-admin@vsp.local}"
readonly VCF_FLEET_LIFECYCLE_PASS="${4:-VMw@re1!VMw@re1!}"
LOG_FILE="${OUTPUT_DIR}/audit.log"

# 3. Traps & Cleanup
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "Error: Script failed with exit code $exit_code." >&2
    fi
}
trap cleanup EXIT

# 4. Functions
log_message() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    if ! command -v df &> /dev/null; then
        echo "Error: Required command 'df' not found." >&2
        exit 1
    fi
}

# 5. Main Logic
main() {
    check_prerequisites
    mkdir -p "$OUTPUT_DIR"
    
    log_message "Starting deployment of Real Time Metrics..."
    df -h > "${OUTPUT_DIR}/disk_usage.txt"
    log_message "Audit complete. Report saved to ${OUTPUT_DIR}/disk_usage.txt"

    # Verify that the required variables have been supplied
    log_message "=== [STEP 1/2] Verifying Environment Variables ==="
    if [ -z "${VCF_FLEET_LIFECYCLE_FQDN}" ] || [ -z "${VCF_FLEET_LIFECYCLE_USER}" ] || [ -z "${VCF_FLEET_LIFECYCLE_PASS}" ]; then
        log_message "❌ Error: One or more environment variables are completely empty."
        log_message "Please run: export vcfOperationsFqdn='...' vcfOperationsToken='...' collectorGroupId='...'"
        exit 1
    fi
    log_message "✅ Environment variables verified"

    # Verify that a connection can be made to the VCF Fleet Lifecycle Endpoint
    log_message "=== [STEP 2/2] Testing API Connectivity ==="
        # Example logic using the inputs
        log_message "----------------------------------------"
        log_message "Connecting to target host..."
        log_message "FQDN:     ${VCF_FLEET_LIFECYCLE_FQDN}"
        log_message "Username: ${VCF_FLEET_LIFECYCLE_USER}"
        log_message "Password: [PROTECTED]"
        log_message "----------------------------------------"
        
        RAW_RESPONSE=$(curl -ks -X POST "https://${VCF_FLEET_LIFECYCLE_FQDN}/api/v1/identity/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data "grant_type=password" \
        --data "username=$VCF_FLEET_LIFECYCLE_USER" \
        --data "password=$VCF_FLEET_LIFECYCLE_PASS")

        HTTP_STATUS=$(log_message "${RAW_RESPONSE}" | tail -n1)
        JSON_BODY=$(log_message "${RAW_RESPONSE}" | sed '$d')

    if [ "$HTTP_STATUS" -ne 200 ]; then
        log_message "❌ API Connection Failed with HTTP Status: ${HTTP_STATUS}"
        log_message "Response from server: ${JSON_BODY}"
        exit 1
    fi
    log_message "✅ API Connection Successful (HTTP 200)"
}

# 6. Entry Point Invocation
main "$@"





