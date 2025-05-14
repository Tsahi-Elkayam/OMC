##############################################
# Jenkins ELK Stack Installation Script
# This script installs a complete Jenkins CI/CD environment
# with Elasticsearch, Logstash, and Kibana for log management
##############################################

# Record start time for duration calculation
$startTime = Get-Date

Write-Host "Starting Jenkins-ELK Stack Kubernetes Deployment..." -ForegroundColor Green
Write-Host "Start Time: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green

# Base paths for different components
$basePath = $PSScriptRoot
$kubernetesPath = Join-Path -Path $basePath -ChildPath "kubernetes"
$namespacesPath = Join-Path -Path $kubernetesPath -ChildPath "namespaces"
$networkingPath = Join-Path -Path $kubernetesPath -ChildPath "networking"
$elasticsearchPath = Join-Path -Path $kubernetesPath -ChildPath "elasticsearch"
$kibanaPath = Join-Path -Path $kubernetesPath -ChildPath "kibana"
$logstashPath = Join-Path -Path $kubernetesPath -ChildPath "logstash"
$jenkinsPath = Join-Path -Path $kubernetesPath -ChildPath "jenkins"

# Function to check if a resource exists
function Test-K8sResource {
    param (
        [string]$type,
        [string]$name,
        [string]$namespace
    )

    if ([string]::IsNullOrEmpty($namespace)) {
        $result = kubectl get $type $name --ignore-not-found
    } else {
        $result = kubectl get $type $name -n $namespace --ignore-not-found
    }

    return ![string]::IsNullOrEmpty($result)
}

# Function to wait for pods to be ready
function Wait-ForPodsReady {
    param (
        [string]$namespace,
        [string]$label,
        [int]$timeoutSeconds = 300,
        [int]$checkIntervalSeconds = 5
    )

    # Adjust check interval based on pod type
    if ($label -eq "app=logstash") {
        # Use longer intervals for Logstash which can take more time to initialize
        $checkIntervalSeconds = 15
        # Default timeout is already set, but can be overridden when calling the function
    }

    Write-Host "Waiting for $label pods in $namespace to be ready..." -ForegroundColor Cyan

    $startTime = Get-Date
    $timeoutTime = $startTime.AddSeconds($timeoutSeconds)
    $lastStatusUpdate = $startTime
    $statusUpdateInterval = New-TimeSpan -Seconds 30  # Only show detailed status every 30 seconds

    do {
        $pods = kubectl get pods -n $namespace -l $label -o json | ConvertFrom-Json
        $allReady = $true
        $readyCount = 0
        $totalCount = 0

        if ($pods.items) {
            $totalCount = $pods.items.Count

            foreach ($pod in $pods.items) {
                if ($pod.status.phase -ne "Running") {
                    $allReady = $false
                } else {
                    $containerReadyCount = 0
                    $totalContainers = $pod.status.containerStatuses.Count

                    foreach ($containerStatus in $pod.status.containerStatuses) {
                        if ($containerStatus.ready) {
                            $containerReadyCount++
                        }
                    }

                    if ($containerReadyCount -eq $totalContainers) {
                        $readyCount++
                    } else {
                        $allReady = $false
                    }
                }
            }
        } else {
            $allReady = $false
        }

        # Current time for timeout and status update checks
        $currentTime = Get-Date

        # Only show detailed status at specified intervals to reduce verbosity
        if (($currentTime - $lastStatusUpdate) -ge $statusUpdateInterval) {
            if ($totalCount -gt 0) {
                Write-Host "Status: $readyCount of $totalCount $label pods are ready..." -ForegroundColor Yellow
            } else {
                Write-Host "Waiting for $label pods to be created..." -ForegroundColor Yellow
            }
            $lastStatusUpdate = $currentTime
        }

        if ($allReady -and $totalCount -gt 0) {
            Write-Host "All $totalCount $label pods are ready!" -ForegroundColor Green
            return $true
        }

        if ($currentTime -gt $timeoutTime) {
            Write-Host "Timeout waiting for $label pods to be ready" -ForegroundColor Red
            return $false
        }

        Start-Sleep -Seconds $checkIntervalSeconds

    } while ($true)
}

# Step 1: Create namespaces
Write-Host "Step 1: Creating namespaces..." -ForegroundColor Blue
kubectl apply -f "$namespacesPath/networks.yaml"
Start-Sleep -Seconds 2

# Step 2: Deploy Elasticsearch
Write-Host "Step 2: Deploying Elasticsearch..." -ForegroundColor Blue
kubectl apply -f "$elasticsearchPath/elasticsearch.yaml"
Wait-ForPodsReady -namespace "elastic-network" -label "app=elasticsearch" -timeoutSeconds 240

# Step 3: Deploy Kibana
Write-Host "Step 3: Deploying Kibana..." -ForegroundColor Blue
kubectl apply -f "$kibanaPath/kibana.yaml"
Wait-ForPodsReady -namespace "elastic-network" -label "app=kibana" -timeoutSeconds 180

# Step 4: Deploy Logstash
Write-Host "Step 4: Deploying Logstash..." -ForegroundColor Blue
kubectl apply -f "$logstashPath/logstash-config.yaml"
kubectl apply -f "$logstashPath/logstash.yaml"
# Longer timeout for Logstash as it can take time to pull the image and initialize
Wait-ForPodsReady -namespace "logstash-network" -label "app=logstash" -timeoutSeconds 360

# Step 5: Create Network Services
Write-Host "Step 5: Creating network services..." -ForegroundColor Blue
kubectl apply -f "$networkingPath/network-policies.yaml"

# Step 6: Set up Jenkins
Write-Host "Step 6: Setting up Jenkins with initial configuration..." -ForegroundColor Blue
kubectl apply -f "$jenkinsPath/jenkins-init-config.yaml"
kubectl apply -f "$jenkinsPath/jenkins-pod-templates.yaml"
kubectl apply -f "$jenkinsPath/jenkins-master.yaml"
Wait-ForPodsReady -namespace "jenkins-network" -label "app=jenkins" -timeoutSeconds 300

# Step 7: Create Kibana dashboard
Write-Host "Step 7: Creating Kibana dashboard for Jenkins logs..." -ForegroundColor Blue
kubectl apply -f "$kibanaPath/kibana-dashboard-config.yaml"
kubectl apply -f "$kibanaPath/kibana-dashboard-job.yaml"

# Calculate installation time
$installEndTime = Get-Date
$installDuration = $installEndTime - $startTime
$formattedDuration = "{0:D2}h:{1:D2}m:{2:D2}s" -f $installDuration.Hours, $installDuration.Minutes, $installDuration.Seconds

# Get cluster information
$kubeContext = kubectl config current-context
$kubeVersion = kubectl version --short 2>$null
$kubeNodes = kubectl get nodes -o json | ConvertFrom-Json
$clusterName = kubectl config view --minify -o jsonpath='{.clusters[0].name}'

# Get NodePort information
Write-Host "`n=====================================================================" -ForegroundColor Green
Write-Host "                JENKINS ELK STACK DEPLOYMENT SUMMARY" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green

Write-Host "`n[INSTALLATION INFO]" -ForegroundColor Yellow
Write-Host "  Installation Date: $($installEndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "  Installation Duration: $formattedDuration" -ForegroundColor White
Write-Host "  Script Version: 1.1.0" -ForegroundColor White

Write-Host "`n[KUBERNETES CLUSTER]" -ForegroundColor Yellow
Write-Host "  Context: $kubeContext" -ForegroundColor White
Write-Host "  Cluster Name: $clusterName" -ForegroundColor White
Write-Host "  Kubernetes Version: $kubeVersion" -ForegroundColor White

Write-Host "`n[NODES]" -ForegroundColor Yellow
foreach ($node in $kubeNodes.items) {
    $nodeName = $node.metadata.name
    $nodeIP = $node.status.addresses | Where-Object { $_.type -eq "InternalIP" } | Select-Object -ExpandProperty address
    $nodeStatus = $node.status.conditions | Where-Object { $_.type -eq "Ready" } | Select-Object -ExpandProperty status
    $nodeRole = $node.metadata.labels.keys | Where-Object { $_ -like "node-role.kubernetes.io*" } | ForEach-Object { $_.Split('/')[1] }
    if (-not $nodeRole) { $nodeRole = "worker" }

    $statusColor = if ($nodeStatus -eq "True") { "Green" } else { "Red" }
    Write-Host "  Node: $nodeName ($nodeRole)" -ForegroundColor White
    Write-Host "    IP: $nodeIP" -ForegroundColor White
    Write-Host "    Status: " -ForegroundColor White -NoNewline
    Write-Host "$nodeStatus" -ForegroundColor $statusColor
}

# Get access URLs
$jenkinsNodePort = kubectl get svc jenkins -n jenkins-network -o jsonpath='{.spec.ports[0].nodePort}'
$kibanaNodePort = kubectl get svc kibana -n elastic-network -o jsonpath='{.spec.ports[0].nodePort}'

# Take first node IP as an example
$firstNodeIP = $kubeNodes.items[0].status.addresses | Where-Object { $_.type -eq "InternalIP" } | Select-Object -ExpandProperty address

Write-Host "`n[DEPLOYED COMPONENTS]" -ForegroundColor Yellow
$jenkinsPods = kubectl get pods -n jenkins-network -l app=jenkins --no-headers | Measure-Object | Select-Object -ExpandProperty Count
$elasticPods = kubectl get pods -n elastic-network -l app=elasticsearch --no-headers | Measure-Object | Select-Object -ExpandProperty Count
$kibana = kubectl get pods -n elastic-network -l app=kibana --no-headers | Measure-Object | Select-Object -ExpandProperty Count
$logstash = kubectl get pods -n logstash-network -l app=logstash --no-headers | Measure-Object | Select-Object -ExpandProperty Count

Write-Host "  Jenkins Instances: $jenkinsPods" -ForegroundColor White
Write-Host "  Elasticsearch Nodes: $elasticPods" -ForegroundColor White
Write-Host "  Kibana Instances: $kibana" -ForegroundColor White
Write-Host "  Logstash Instances: $logstash" -ForegroundColor White

Write-Host "`n[ACCESS INFORMATION]" -ForegroundColor Yellow
Write-Host "  Jenkins:" -ForegroundColor White
Write-Host "    URL: http://${firstNodeIP}:${jenkinsNodePort}" -ForegroundColor Cyan
Write-Host "    Username: admin" -ForegroundColor Cyan
Write-Host "    Password: admin123" -ForegroundColor Cyan
Write-Host "  Kibana:" -ForegroundColor White
Write-Host "    URL: http://${firstNodeIP}:${kibanaNodePort}" -ForegroundColor Cyan

Write-Host "`n[VERIFICATION STEPS]" -ForegroundColor Yellow
Write-Host "  1. Access Jenkins at the URL above and login" -ForegroundColor White
Write-Host "  2. Run the curl-build job in Jenkins" -ForegroundColor White
Write-Host "  3. Check logs in Kibana's 'Jenkins Logs Dashboard'" -ForegroundColor White

Write-Host "`n[TROUBLESHOOTING]" -ForegroundColor Yellow
Write-Host "  • If node IP above is incorrect, run: kubectl get nodes -o wide" -ForegroundColor White
Write-Host "  • For pod status, run: kubectl get pods --all-namespaces" -ForegroundColor White
Write-Host "  • Check logs with: kubectl logs -n <namespace> <pod-name>" -ForegroundColor White

Write-Host "`n=====================================================================" -ForegroundColor Green
Write-Host "                       DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
