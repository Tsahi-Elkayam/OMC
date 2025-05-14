<#
.SYNOPSIS
    Reset script for Docker Desktop with Kubernetes enabled
.DESCRIPTION
    This PowerShell script automates the process of resetting Kubernetes in Docker Desktop.
    It performs the following tasks:
    - Cleans up Kubernetes resources
    - Forces removal of ALL Docker containers using multiple methods
    - Deletes all images including Kubernetes ones
    - Performs complete Docker system cleanup
.NOTES
    Requires: Docker Desktop with Kubernetes enabled, PowerShell
#>

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-LogMessage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "Info" { Write-Host $formattedMessage -ForegroundColor Green }
        "Warning" { Write-Host $formattedMessage -ForegroundColor Yellow }
        "Error" { Write-Host $formattedMessage -ForegroundColor Red }
    }
}

function Test-CommandExists {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $exists = Get-Command -Name $Command -ErrorAction SilentlyContinue
    return $null -ne $exists
}

function Stop-AllContainers {
    Write-LogMessage "Forcing removal of ALL Docker containers..." -Level "Info"

    # Multiple approaches to ensure ALL containers are stopped and removed
    try {
        # 1. List all containers (including those not shown by default)
        $allContainers = @(docker ps -a -q)

        if ($allContainers -and $allContainers.Count -gt 0) {
            # 2. Kill all running containers first (in case stop doesn't work)
            Write-LogMessage "Killing all running containers..."
            $runningContainers = @(docker ps -q)
            if ($runningContainers -and $runningContainers.Count -gt 0) {
                docker kill $runningContainers 2>$null
            }

            # 3. Stop all containers (just to be sure)
            Write-LogMessage "Stopping all containers..."
            docker stop $allContainers 2>$null

            # 4. Remove all containers with force
            Write-LogMessage "Removing all containers forcefully..."
            docker rm -f $allContainers 2>$null

            # 5. Additional docker container prune for any leftovers
            Write-LogMessage "Running container prune for any leftovers..."
            docker container prune -f
        }
        else {
            Write-LogMessage "No containers found to remove"
        }

        # 6. Check if any containers still remain
        $remainingContainers = @(docker ps -a -q)
        if ($remainingContainers -and $remainingContainers.Count -gt 0) {
            Write-LogMessage "Some containers could not be removed automatically" -Level "Warning"
            Write-LogMessage "Trying one more aggressive approach..." -Level "Info"

            # Loop through each container and try to kill/remove individually
            foreach ($container in $remainingContainers) {
                try {
                    Write-LogMessage "Forcing removal of container: $container"
                    docker kill $container 2>$null
                    docker rm -f $container
                }
                catch {
                    # Try direct system kill if possible
                    Write-LogMessage "Could not remove container $container using docker commands" -Level "Warning"
                }
            }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-LogMessage "Error during container cleanup: $($errorMsg)" -Level "Warning"
    }

    # Final check
    $finalCheck = @(docker ps -a -q)
    if ($finalCheck -and $finalCheck.Count -gt 0) {
        Write-LogMessage "Warning: $($finalCheck.Count) containers could not be removed" -Level "Warning"
        Write-LogMessage "You may need to restart Docker Desktop to fully clean up" -Level "Warning"
    }
    else {
        Write-LogMessage "All containers have been successfully removed"
    }
}

function Remove-AllImages {
    Write-LogMessage "Removing ALL Docker images..."

    # Check if any containers are still running
    $remainingContainers = @(docker ps -a -q)
    if ($remainingContainers -and $remainingContainers.Count -gt 0) {
        Write-LogMessage "Cannot safely remove all images while containers exist" -Level "Warning"
        Write-LogMessage "Attempting additional container cleanup..." -Level "Info"
        Stop-AllContainers
    }

    try {
        # Get all image IDs
        $allImages = @(docker images -a -q)

        if ($allImages -and $allImages.Count -gt 0) {
            Write-LogMessage "Found $($allImages.Count) images to remove"

            # Try to remove all images in a single command first
            try {
                Write-LogMessage "Attempting bulk image removal..."
                docker rmi -f $allImages
            }
            catch {
                # If bulk removal fails, try removing images one by one
                Write-LogMessage "Bulk removal failed, trying individual removal..." -Level "Warning"

                foreach ($image in $allImages) {
                    try {
                        Write-LogMessage "Removing image: $image"
                        docker rmi -f $image
                    }
                    catch {
                        $errorMsg = $_.Exception.Message
                        Write-LogMessage "Failed to remove image $image - $($errorMsg)" -Level "Warning"
                    }
                }
            }

            # Final image prune to catch any leftovers
            Write-LogMessage "Running final image prune..."
            docker image prune -a -f
        }
        else {
            Write-LogMessage "No images found to remove"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-LogMessage "Error during image cleanup: $($errorMsg)" -Level "Warning"
    }

    # Check if any images remain
    $remainingImages = @(docker images -a -q)
    if ($remainingImages -and $remainingImages.Count -gt 0) {
        Write-LogMessage "Warning: $($remainingImages.Count) images could not be removed" -Level "Warning"
        Write-LogMessage "Performing second container cleanup..." -Level "Info"
        Stop-AllContainers

        # Try one more time to remove remaining images
        try {
            Write-LogMessage "Second attempt to remove remaining images..."
            docker rmi -f $remainingImages
            docker image prune -a -f
        }
        catch {
            Write-LogMessage "Some images still could not be removed" -Level "Warning"
        }
    }
    else {
        Write-LogMessage "All images have been successfully removed"
    }
}

function Remove-KubernetesResources {
    Write-LogMessage "Removing Kubernetes resources..."

    # Check if kubectl is available
    if (-not (Test-CommandExists "kubectl")) {
        Write-LogMessage "kubectl command not found. Skipping Kubernetes resource cleanup." -Level "Warning"
        return
    }

    # Wait for Kubernetes to be ready
    $retry = 0
    $maxRetry = 5
    $ready = $false

    while (-not $ready -and $retry -lt $maxRetry) {
        try {
            kubectl get nodes | Out-Null
            $ready = $true
        }
        catch {
            $retry++
            Write-LogMessage "Waiting for Kubernetes to be ready... ($retry/$maxRetry)" -Level "Warning"
            Start-Sleep -Seconds 3
        }
    }

    if (-not $ready) {
        Write-LogMessage "Kubernetes is not ready. Proceeding with best-effort cleanup." -Level "Warning"
    }

    try {
        # Try to delete all resources in all namespaces
        Write-LogMessage "Attempting to delete all Kubernetes resources in all namespaces..."

        try {
            # Get all namespaces except system ones
            $namespaces = @(kubectl get namespaces -o jsonpath="{.items[*].metadata.name}" 2>$null | ForEach-Object { $_.Split() } | Where-Object { $_ -notin @("kube-system", "kube-public", "kube-node-lease", "default") })

            if ($namespaces -and $namespaces.Count -gt 0) {
                foreach ($namespace in $namespaces) {
                    try {
                        Write-LogMessage "Deleting all resources in namespace: $namespace"
                        kubectl delete all --all -n $namespace 2>$null
                        kubectl delete namespace $namespace 2>$null
                    }
                    catch {
                        Write-LogMessage "Error cleaning up namespace $namespace" -Level "Warning"
                    }
                }
            }

            # Clean up default namespace
            Write-LogMessage "Cleaning up resources in default namespace"
            kubectl delete all --all -n default 2>$null

            # Delete other resource types
            kubectl delete pvc --all --all-namespaces 2>$null
            kubectl delete pv --all 2>$null
            kubectl delete configmaps --all --all-namespaces 2>$null
            kubectl delete secrets --all --all-namespaces 2>$null
        }
        catch {
            Write-LogMessage "Error during Kubernetes resource cleanup" -Level "Warning"
        }
    }
    catch {
        Write-LogMessage "Could not perform Kubernetes cleanup" -Level "Warning"
    }

    Write-LogMessage "Kubernetes resource cleanup completed"
}

function Clear-DockerSystem {
    Write-LogMessage "Performing complete Docker system cleanup..."

    try {
        # Remove unused volumes
        Write-LogMessage "Removing all volumes..."
        docker volume prune -f

        # Remove all networks
        Write-LogMessage "Removing all networks..."
        docker network prune -f

        # System prune (aggressive)
        Write-LogMessage "Performing aggressive system prune..."
        docker system prune -a -f --volumes

        Write-LogMessage "Docker system cleanup completed successfully"
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-LogMessage "Error during system cleanup: $($errorMsg)" -Level "Warning"
    }
}

function Second-Reset {
    Write-LogMessage "Performing second reset cycle..." -Level "Info"

    # Try to clean up any remaining containers one last time
    Stop-AllContainers

    # Try to remove any remaining images
    try {
        $remainingImages = @(docker images -a -q)
        if ($remainingImages -and $remainingImages.Count -gt 0) {
            Write-LogMessage "Found $($remainingImages.Count) images in second reset cycle"
            docker rmi -f $remainingImages 2>$null
        }
    }
    catch {
        Write-LogMessage "Error in second image reset" -Level "Warning"
    }

    # Final system prune
    Write-LogMessage "Final system cleanup..."
    docker system prune -a -f --volumes

    Write-LogMessage "Second reset cycle completed"
}

function Main {
    Write-LogMessage "=== STARTING COMPLETE DOCKER/KUBERNETES RESET SCRIPT ===" -Level "Info"

    # 1. Kubernetes resources cleanup first
    Remove-KubernetesResources

    # 2. Force remove all containers
    Stop-AllContainers

    # 3. Force remove all images
    Remove-AllImages

    # 4. Complete Docker system cleanup
    Clear-DockerSystem

    # 5. Second reset cycle as requested
    Second-Reset

    Write-LogMessage "=== RESET PROCESS COMPLETED ===" -Level "Info"
    Write-LogMessage "If any errors occurred or images remain, please manually restart Docker Desktop and try again" -Level "Info"
    Write-LogMessage "To reset Kubernetes, go to Docker Desktop Settings > Kubernetes > Reset Kubernetes Cluster" -Level "Info"
}

# Execute the main function
Main
