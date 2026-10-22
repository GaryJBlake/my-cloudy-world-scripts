#!/usr/bin/env bash

# =============================================================================
# Script Name : configure_vcenter_backup.sh
# Description : Triggers the deployment of the Real Time Metrics component.
# Author      : Gary Blake
# Usage       : ./configure_vcenter_backup.sh [log directory] [config json]
# =============================================================================


# 1. Shell Options & Error Handling
set -euo pipefail

# 2. Environment & Global Variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_DIR="${1:-../logs}"
readonly CONFIG_JSON="${2:-backup-config.json}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="${OUTPUT_DIR}/configure_vcenter_backup-${TIMESTAMP}.log"

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

check_json_file() {
    # 1. Check if the file exists and is readable
    if [[ ! -f "${CONFIG_JSON}" ]]; then
        log_message "❌ Error: Configuration file '${CONFIG_JSON}' not found or is not a file."
        exit 1
    fi

    # 2. Check if the file contains valid JSON syntax
    if ! jq empty "${CONFIG_JSON}" 2>/dev/null; then
        log_message "❌ Error: File '${CONFIG_JSON}' exists but is not valid JSON."
        exit 1
    fi

    log_message "✅ Configuration file '${CONFIG_JSON}' verified successfully."

    IFS=$'\t' read -r VCENTER_FQDN VCENTER_USER VCENTER_PASS < <(
        jq -r '[.vcenterFqdn, .vcenterUser, .vcenterPass] | @tsv' ${CONFIG_JSON}
    )

    IFS=$'\t' read -r SFTP_SERVER_IP SFTP_DIR SFTP_USER SFTP_PASS SFTP_ENCRYPT HOUR MINUTE RETENTION < <(
        jq -r '[.sftpServerIp, .sftpDirectory, .sftpUser, .sftpPass, .encryptionPassphrase, .backupSchedule.hour, .backupSchedule.minute, .backupSchedule.retention] | @tsv' backup-config.json
    )
}

verify_connection_variables() {
    # Verify that the required variables have been supplied
    if [ -z "${VCENTER_FQDN}" ] || [ -z "${VCENTER_USER}" ] || [ -z "${VCENTER_PASS}" ]; then
        log_message "❌ Error: One or more environment variables are completely empty."
        log_message "Please run entering: [vcenter fqdn] [username] [password]"
        exit 1
    fi
    log_message "✅ Verified Connection variables"
}

verify_connection() {
    # Verify that a connection can be made to vCenter Endpoint
    log_message "Connecting to target vCenter..."
    log_message "---------------------------------------------------------------------------------"
    log_message "vCenter FQDN:               ${VCENTER_FQDN}"
    log_message "Username:                   ${VCENTER_USER}"
    log_message "Password:                   [PROTECTED]"
    log_message "---------------------------------------------------------------------------------"

    # 1. Capture HTTP status and JSON response in a single curl call
    RESPONSE=$(curl -s -w "\n%{http_code}" -k -X POST "https://${VCENTER_FQDN}/api/session" \
        -u "${VCENTER_USER}:${VCENTER_PASS}")

    # Separate body and status code
    HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
    JSON_BODY=$(echo "$RESPONSE" | sed '$d')

    # 2. Extract token using jq (removes surrounding quotes)
    VCENTER_TOKEN=$(echo "${JSON_BODY}" | jq -r '.' 2>/dev/null)

    # 3. Validation Logic
    if [[ "${HTTP_STATUS}" != "200" && "${HTTP_STATUS}" != "201" ]] || [[ "${VCENTER_TOKEN}" == "null" || -z "${VCENTER_TOKEN}" ]]; then
        log_message "❌ API Connection Failed with HTTP Status: ${HTTP_STATUS:-000}"
        log_message "❌ Response from server: ${JSON_BODY}"
        exit 1
    fi

    log_message "✅ API Connection Successful (HTTP ${HTTP_STATUS})"
    log_message "✅ Authentication Token: ${VCENTER_TOKEN}"
}

configure_vcenter_backup() {
    # Configure SFTP Backup Location and Schedule for vCenter
    log_message "Configuring SFTP backup location and schedule for vCenter"
    log_message "Settings that will be used to configure the SFTP backup location..."
    log_message "---------------------------------------------------------------------------------"
    log_message "SFTP Server IP Address:     ${SFTP_SERVER_IP}"
    log_message "SFTP Directory:             ${SFTP_DIR}"
    log_message "SFTP User:                  ${SFTP_USER}"
    log_message "SFTP Password:              [PROTECTED]"
    log_message "SFTP Encryption Passphrase: [PROTECTED]"
    log_message "Backup Hour:                ${HOUR}"
    log_message "Backup Minute:              ${MINUTE}"
    log_message "Retention:                  ${RETENTION}"
    log_message "---------------------------------------------------------------------------------"

    VCENTER_CONFIG=$(curl -S -ks -X GET "https://${VCENTER_FQDN}/api/appliance/recovery/backup/schedules" \
    --header "vmware-api-session-id: ${VCENTER_TOKEN}" \
    --header "Content-Type: application/json" \
    --header "Accept: application/json")

    cat << EOF > sftp-backup-location-vcenter.json
{
    "schedule": "default",
    "spec": {
        "location": "sftp://${SFTP_SERVER_IP}${SFTP_DIR}",
        "location_user": "${SFTP_USER}",
        "location_password": "${SFTP_PASS}",
        "parts": ["supervisors", "seat", "common"],
        "backup_password": "${SFTP_ENCRYPT}",
        "recurrence_info": { "days": [], "hour": ${HOUR}, "minute": ${MINUTE} },
        "retention_info": { "max_count": ${RETENTION} }
    }
}
EOF
    
    if [[ "${VCENTER_CONFIG}" == "{}" ]]; then
        log_message "Attempting to configure SFTP backup location for vCenter..."

        curl -S -ks -X POST "https://${VCENTER_FQDN}/api/appliance/recovery/backup/schedules" \
        --header "vmware-api-session-id: ${VCENTER_TOKEN}" \
        --header "Content-Type: application/json" \
        --header "Accept: application/json" \
        -d @sftp-backup-location-vcenter.json

        log_message "Verifying SFTP backup location for vCenter has been configured..."
        VCENTER_CONFIG=$(curl -S -ks -X GET "https://${VCENTER_FQDN}/api/appliance/recovery/backup/schedules" \
        --header "vmware-api-session-id: ${VCENTER_TOKEN}" \
        --header "Content-Type: application/json" \
        --header "Accept: application/json")
        if [[ "${VCENTER_CONFIG}" != "{}" ]]; then
            log_message "✅ SFTP backup location configured successfully for ${VCENTER_FQDN}"
        fi
    else 
        log_message "⚠️ Warning: SFTP backup location already configured for ${VCENTER_FQDN}"
    fi
}

perform_vcenter_manual_backup() {
    log_message "Verifying SFTP backup configuration by running a manual backup of vCenter..."

    JSON_PAYLOAD=$(jq -n \
        --arg loc "sftp://${SFTP_SERVER_IP}${SFTP_DIR}" \
        --arg user "${SFTP_USER}" \
        --arg pass "${SFTP_PASS}" \
        --arg enc "${SFTP_ENCRYPT}" \
        '{
            location: $loc,
            location_user: $user,
            location_password: $pass,
            parts: ["supervisors", "seat", "common"],
            backup_password: $enc,
            location_type: "SFTP",
            comment: ""
        }')

    JOB_ID=$(curl -S -ks -X POST "https://${VCENTER_FQDN}/api/appliance/recovery/backup/job" \
    --header "vmware-api-session-id: ${VCENTER_TOKEN}" \
    --header "Content-Type: application/json" \
    --header "Accept: application/json" \
    -d "${JSON_PAYLOAD}" | jq -r ".id")

    while curl -ks -X GET "https://${VCENTER_FQDN}/api/appliance/recovery/backup/job/${JOB_ID}" \
        --header "vmware-api-session-id: ${VCENTER_TOKEN}" \
        --header "Content-Type: application/json" \
        --header "Accept: application/json" \
        | jq '{state: .state}' \
        | grep -q "INPROGRESS"; do
        log_message "Backup still 'In Progress' state... waiting 30 seconds."
        sleep 30
        
    done

    JOB_STATUS=$(curl -ks -X GET "https://${VCENTER_FQDN}/api/appliance/recovery/backup/job/${JOB_ID}" \
        --header "vmware-api-session-id: ${VCENTER_TOKEN}" \
        --header "Content-Type: application/json" \
        --header "Accept: application/json" \
        | jq -r ".state")
    if [ "${JOB_STATUS}" == "SUCCEEDED" ]; then
        log_message "✅ Manual backup completed successfully for ${VCENTER_FQDN}"
    else 
        log_message "❌ Manual backup failed for ${VCENTER_FQDN} please investigate"
    fi
}

# 5. Main Logic
main() {
    check_json_file
    mkdir -p "$OUTPUT_DIR"
    
    log_message "Starting configuration of SFTP backup for vCenter..."

    log_message "==== [STEP 1/4] Verifying Connection Variables =================================="
    verify_connection_variables

    log_message "=== [STEP 2/4] Testing API Connectivity ========================================="
    verify_connection

    log_message "=== [STEP 3/4] Configuring SFTP Backup and Schedule for vCenter ================="
    configure_vcenter_backup
    
    # Run manual backup of vCenter
    log_message "=== [STEP 4/4] Running a manual backup of vCenter ==============================="
    perform_vcenter_manual_backup
}

# 6. Entry Point Invocation
main "$@"
