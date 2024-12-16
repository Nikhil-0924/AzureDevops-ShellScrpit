# AzureDevops-ShellScrpit
Azure Devops - PipelineScript


#!/bin/bash

-> Global Configuration
ACR_NAME="youracrname"  # Replace with your Azure Container Registry name (e.g., "myacr")
RESOURCE_GROUP="your-resource-group"  # Replace with your Azure Resource Group
DOCKERFILES=("Dockerfile1" "Dockerfile2" "Dockerfile3")  # List of Dockerfiles to track
IMAGE_PREFIX="yourimageprefix"  # Prefix for the image names in ACR
LOG_FILE="/var/log/azure_acr_push.log"
DATE_FORMAT="%Y-%m-%d_%H-%M-%S"

-> Function Definitions 

-> Logs messages with timestamp
log_message() {
    local message="$1"
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$LOG_FILE"
}

-> Login to Azure Container Registry
login_to_acr() {
    log_message "INFO: Logging in to Azure Container Registry: $ACR_NAME"
    if ! az acr login --name "$ACR_NAME"; then
        log_message "ERROR: Failed to log in to ACR: $ACR_NAME"
        return 1
    fi
    log_message "INFO: Successfully logged in to ACR: $ACR_NAME"
}

-> Check if Dockerfile has been updated in the Git repo

check_dockerfile_updates() {
    local dockerfile="$1"
    if git diff --name-only HEAD~1 | grep -q "$dockerfile"; then
        log_message "INFO: Dockerfile updated: $dockerfile"
        return 0
    else
        log_message "INFO: No updates found for Dockerfile: $dockerfile"
        return 1
    fi
}

-> Build, Tag, and Push Docker image to ACR

build_and_push_image() {
    local dockerfile="$1"
    local image_name image_tag

    image_name="${IMAGE_PREFIX}/${dockerfile,,}"  # Lowercase image name
    image_tag="$(date +"$DATE_FORMAT")"  # Create a tag using the current date

    log_message "INFO: Building Docker image: $image_name:$image_tag using $dockerfile"
    
    if ! docker build -t "${ACR_NAME}.azurecr.io/${image_name}:${image_tag}" -f "$dockerfile" .; then
        log_message "ERROR: Failed to build image: ${ACR_NAME}.azurecr.io/${image_name}:${image_tag}"
        return 1
    fi

    log_message "INFO: Successfully built image: ${ACR_NAME}.azurecr.io/${image_name}:${image_tag}"

    log_message "INFO: Pushing image to ACR: ${ACR_NAME}.azurecr.io/${image_name}:${image_tag}"
    if ! docker push "${ACR_NAME}.azurecr.io/${image_name}:${image_tag}"; then
        log_message "ERROR: Failed to push image to ACR: ${ACR_NAME}.azurecr.io/${image_name}:${image_tag}"
        return 1
    fi

    log_message "INFO: Successfully pushed image to ACR: ${ACR_NAME}.azurecr.io/${image_name}:${image_tag}"
}

-> Main function to process Dockerfiles
main() {
    log_message "INFO: Starting the process to build and push Docker images to ACR"

    if ! login_to_acr; then
        log_message "ERROR: Could not log in to ACR. Exiting."
        exit 1
    fi

    for dockerfile in "${DOCKERFILES[@]}"; do
        log_message "INFO: Checking if Dockerfile has been updated: $dockerfile"

        if check_dockerfile_updates "$dockerfile"; then
            if ! build_and_push_image "$dockerfile"; then
                log_message "ERROR: Failed to build and push image for $dockerfile"
            fi
        else
            log_message "INFO: Skipping image build for $dockerfile (No changes detected)"
        fi
    done

    log_message "INFO: Docker image build and push process completed successfully"
}

-> Execute the main function
main
