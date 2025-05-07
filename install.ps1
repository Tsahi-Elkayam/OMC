##############################################
# Jenkins ELK Stack Installation Script
# This script installs a complete Jenkins CI/CD environment 
# with Elasticsearch, Logstash, and Kibana for log management
##############################################

Write-Host "Starting Jenkins-ELK Stack Kubernetes Deployment..." -ForegroundColor Green

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
        [int]$timeoutSeconds = 300
    )
    
    Write-Host "Waiting for $label pods in $namespace to be ready..." -ForegroundColor Cyan
    
    $startTime = Get-Date
    $timeoutTime = $startTime.AddSeconds($timeoutSeconds)
    
    do {
        $pods = kubectl get pods -n $namespace -l $label -o json | ConvertFrom-Json
        $allReady = $true
        
        foreach ($pod in $pods.items) {
            if ($pod.status.phase -ne "Running") {
                $allReady = $false
                break
            }
            
            foreach ($containerStatus in $pod.status.containerStatuses) {
                if (-not $containerStatus.ready) {
                    $allReady = $false
                    break
                }
            }
            
            if (-not $allReady) {
                break
            }
        }
        
        if ($allReady -and $pods.items.Count -gt 0) {
            Write-Host "All $($pods.items.Count) $label pods are ready!" -ForegroundColor Green
            return $true
        }
        
        if ((Get-Date) -gt $timeoutTime) {
            Write-Host "Timeout waiting for $label pods to be ready" -ForegroundColor Red
            return $false
        }
        
        Write-Host "Waiting for $label pods to be ready ($($pods.items.Count) found, not all ready)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
    } while ($true)
}

# Step 1: Create namespaces
Write-Host "Step 1: Creating namespaces..." -ForegroundColor Blue
kubectl apply -f networks.yaml
Start-Sleep -Seconds 2

# Step 2: Deploy Elasticsearch
Write-Host "Step 2: Deploying Elasticsearch..." -ForegroundColor Blue
kubectl apply -f elasticsearch.yaml
Wait-ForPodsReady -namespace "elastic-network" -label "app=elasticsearch" -timeoutSeconds 240

# Step 3: Deploy Kibana
Write-Host "Step 3: Deploying Kibana..." -ForegroundColor Blue
kubectl apply -f kibana.yaml
Wait-ForPodsReady -namespace "elastic-network" -label "app=kibana" -timeoutSeconds 180

# Step 4: Deploy Logstash
Write-Host "Step 4: Deploying Logstash..." -ForegroundColor Blue
kubectl apply -f logstash-config.yaml
kubectl apply -f logstash.yaml
Wait-ForPodsReady -namespace "logstash-network" -label "app=logstash" -timeoutSeconds 180

# Step 5: Create Network Services
Write-Host "Step 5: Creating network services..." -ForegroundColor Blue
kubectl apply -f network-policies.yaml

# Step 6: Set up Jenkins
Write-Host "Step 6: Setting up Jenkins with initial configuration..." -ForegroundColor Blue
kubectl apply -f jenkins-init-config.yaml
kubectl apply -f jenkins-pod-templates.yaml
kubectl apply -f jenkins-master.yaml
Wait-ForPodsReady -namespace "jenkins-network" -label "app=jenkins" -timeoutSeconds 300

# Step 7: Create Kibana dashboard
Write-Host "Step 7: Creating Kibana dashboard for Jenkins logs..." -ForegroundColor Blue
kubectl apply -f kibana-dashboard-config.yaml
kubectl apply -f kibana-dashboard-job.yaml

# Get NodePort information
Write-Host "`nDeployment complete! Getting access information..." -ForegroundColor Green

# Get Jenkins NodePort
$jenkinsNodePort = kubectl get svc jenkins -n jenkins-network -o jsonpath='{.spec.ports[0].nodePort}'
Write-Host "Jenkins is available at: http://<node-ip>:$jenkinsNodePort" -ForegroundColor Cyan
Write-Host "    Username: admin" -ForegroundColor Cyan
Write-Host "    Password: admin123" -ForegroundColor Cyan

# Get Kibana NodePort
$kibanaNodePort = kubectl get svc kibana -n elastic-network -o jsonpath='{.spec.ports[0].nodePort}'
Write-Host "Kibana is available at: http://<node-ip>:$kibanaNodePort" -ForegroundColor Cyan

Write-Host "`nTo get your node IP, run:" -ForegroundColor Yellow
Write-Host "    kubectl get nodes -o wide" -ForegroundColor Yellow

Write-Host "`nVerify the installation by running the curl-build job in Jenkins" -ForegroundColor Green
Write-Host "and checking the logs in Kibana's 'Jenkins Logs Dashboard'" -ForegroundColor Green
