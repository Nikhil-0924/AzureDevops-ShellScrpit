#!/bin/bash

# ======= Global Configuration =======
ACR_NAME="youracrname"                          # Azure Container Registry name
DOCKERFILES=("Dockerfile1" "Dockerfile2" "Dockerfile3")  # List of Dockerfiles
MANIFEST_FILES=("manifest1.yaml" "manifest2.yaml" "manifest3.yaml")  # Kubernetes manifests
IMAGE_PREFIX="yourimageprefix"                 # Image prefix for ACR images
GIT_REPO="https://<ACCESS-TOKEN>@dev.azure.com/<ORG-NAME>/<PROJECT>/_git/<REPO-NAME>"
BUILD_TAG=$(date +"%Y%m%d%H%M%S")              # Build tag to version the image
TMP_DIR="/tmp/acr_repo"

# ======= Function Definitions =======

# Logs messages with timestamp
log_message() {
    local message="$1"
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
}

# Login to ACR
login_to_acr() {
    log_message "INFO: Logging into ACR: $ACR_NAME"
    if ! az acr login --name "$ACR_NAME"; then
        log_message "ERROR: Failed to log in to ACR: $ACR_NAME"
        exit 1
    fi
    log_message "INFO: Successfully logged into ACR: $ACR_NAME"
}

# Check if Dockerfile has changed using Git
check_if_dockerfile_updated() {
    local dockerfile="$1"
    if git diff --name-only HEAD~1 | grep -q "$dockerfile"; then
        log_message "INFO: Dockerfile updated: $dockerfile"
        return 0
    else
        log_message "INFO: No updates detected for Dockerfile: $dockerfile"
        return 1
    fi
}

# Build and push Docker image
build_and_push_image() {
    local dockerfile="$1"
    local image_name
    image_name="${IMAGE_PREFIX}/$(basename "$dockerfile" | tr '[:upper:]' '[:lower:]')"
    local image_tag="${ACR_NAME}.azurecr.io/${image_name}:${BUILD_TAG}"

    log_message "INFO: Building Docker image: $image_tag from $dockerfile"
    if ! docker build -f "$dockerfile" -t "$image_tag" .; then
        log_message "ERROR: Failed to build image: $image_tag"
        exit 1
    fi

    log_message "INFO: Pushing Docker image: $image_tag to ACR"
    if ! docker push "$image_tag"; then
        log_message "ERROR: Failed to push image: $image_tag"
        exit 1
    fi
    log_message "INFO: Successfully pushed image: $image_tag"
}

# Update Kubernetes manifest file
update_kubernetes_manifest() {
    local manifest="$1"
    local image_name
    local image_tag

    image_name="${IMAGE_PREFIX}/$(basename "$manifest" | sed 's/.yaml//g' | tr '[:upper:]' '[:lower:]')"
    image_tag="${ACR_NAME}.azurecr.io/${image_name}:${BUILD_TAG}"

    log_message "INFO: Updating image in Kubernetes manifest: $manifest"
    if ! sed -i "s|image:.*|image: $image_tag|g" "$TMP_DIR/$manifest"; then
        log_message "ERROR: Failed to update Kubernetes manifest: $manifest"
        exit 1
    fi
    log_message "INFO: Successfully updated image in Kubernetes manifest: $manifest"
}

# Commit and push changes to Git
commit_and_push_changes() {
    log_message "INFO: Committing changes to Azure DevOps Git"
    git add .
    git commit -m "Updated image tags in Kubernetes manifests"
    git push
}

# Main function to build, push, and update Kubernetes manifests
main() {
    log_message "INFO: Starting the process to build, push images, and update manifests"

    # Step 1: Log in to Azure ACR
    login_to_acr

    # Step 2: Clone the Azure DevOps Git repo
    log_message "INFO: Cloning Git repository: $GIT_REPO"
    if ! git clone "$GIT_REPO" "$TMP_DIR"; then
        log_message "ERROR: Failed to clone the repository"
        exit 1
    fi
    cd "$TMP_DIR" || exit 1

    # Step 3: Loop through Dockerfiles
    for i in "${!DOCKERFILES[@]}"; do
        local dockerfile="${DOCKERFILES[$i]}"
        local manifest="${MANIFEST_FILES[$i]}"

        # Step 4: Check if Dockerfile has been updated
        if check_if_dockerfile_updated "$dockerfile"; then
            # Step 5: Build and push Docker image
            build_and_push_image "$dockerfile"
            # Step 6: Update the corresponding Kubernetes manifest file
            update_kubernetes_manifest "$manifest"
        else
            log_message "INFO: Skipping image build for $dockerfile (No changes detected)"
        fi
    done

    # Step 7: Commit and push Kubernetes manifest changes to Git
    commit_and_push_changes

    # Step 8: Clean up
    log_message "INFO: Cleaning up temporary files"
    rm -rf "$TMP_DIR"

    log_message "INFO: Process completed successfully"
}

# Run the main function
main
