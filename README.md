# Jenkins CI/CD Environment with ELK Stack on Kubernetes

This project implements a complete CI/CD environment using Jenkins and the ELK (Elasticsearch, Logstash, Kibana) stack for log management, all deployed on Kubernetes.

## Architecture Overview

The system is composed of three isolated Kubernetes namespaces:

1. **jenkins-network**: Contains Jenkins master and slave nodes
2. **elastic-network**: Contains Elasticsearch cluster and Kibana
3. **logstash-network**: Contains Logstash for log processing

### Components:

- **Jenkins Master**: CI/CD server with pipeline support
- **Jenkins Slaves**: Build agents running in pods
- **Elasticsearch**: Distributed search and analytics engine for logs
- **Logstash**: Log processing pipeline
- **Kibana**: Log visualization dashboard

### Network Topology:

```
Internet
   │
   ├─────► Jenkins Master (NodePort) ─────┐
   │                                      │
   └─────► Kibana (NodePort)              v
                      ▲                Jenkins Slaves
                      │                    │
                      │                    v
                Elasticsearch ◄───── Logstash
                (3 nodes)            (TCP 5045)
```

### Security:

Network policies strictly control communication between components:
- Jenkins master can communicate with Jenkins slaves and Logstash
- Logstash can communicate with Elasticsearch
- Jenkins slaves can only communicate with Jenkins master

## Prerequisites

- Kubernetes cluster (1.19+)
- kubectl configured to communicate with your cluster
- PowerShell for running the installation script

## Installation

1. Clone this repository:
```
git clone https://github.com/yourusername/jenkins-elk-k8s.git
cd jenkins-elk-k8s
```

2. Run the PowerShell installation script:
```
.\install.ps1
```

The script will:
- Create all required namespaces
- Deploy Elasticsearch and Kibana
- Deploy Logstash with proper configuration
- Deploy Jenkins master and configure it with the required plugins
- Apply network policies to secure the environment
- Create the Kibana dashboard for Jenkins logs

## Verification

After installation completes, verify the deployment:

1. **Jenkins**:
   - Access Jenkins UI at `http://<node-ip>:<jenkins-nodeport>`
   - Login with username: `admin`, password: `admin123`
   - Verify the curl-build job is created

2. **Kibana**:
   - Access Kibana UI at `http://<node-ip>:<kibana-nodeport>`
   - Navigate to Dashboard and find "Jenkins Logs Dashboard"

3. **Log Flow**:
   - Run the curl-build job in Jenkins
   - Verify logs appear in Kibana dashboard

## Usage

### CURL Pipeline

The system comes with a pre-configured Jenkins pipeline that:
1. Installs required dependencies
2. Clones the CURL project from GitHub
3. Builds CURL from source
4. Runs CURL tests
5. Archives the build artifacts

To execute the pipeline:
1. Login to Jenkins
2. Navigate to the "curl-build" job
3. Click "Build Now"

### Accessing Logs

1. Open Kibana dashboard
2. Select "Jenkins Logs Dashboard"
3. Filter logs by job, build number, or log level

## Troubleshooting

### Common Issues:

1. **Jenkins to Logstash Connection Issues**:
   - Verify network policies are correctly applied
   - Check Logstash is running: `kubectl get pods -n logstash-network`
   - Check logs: `kubectl logs -n logstash-network deployment/logstash`

2. **Missing Logs in Elasticsearch**:
   - Verify Elasticsearch cluster health: `kubectl exec -n elastic-network elasticsearch-0 -- curl -X GET "localhost:9200/_cluster/health"`
   - Check Logstash output configuration

3. **Network Policy Issues**:
   - Temporarily disable network policies for debugging
   - Use a test pod to verify connectivity between components

## Scaling

- **Jenkins Slaves**: Will automatically scale with the Jenkins Kubernetes plugin
- **Elasticsearch**: Modify replicas in elasticsearch.yaml
- **Logstash**: Modify replicas in logstash.yaml for higher throughput

## Customization

- **Jenkins Plugins**: Modify the plugin list in jenkins-master.yaml
- **Logstash Filters**: Edit the filter section in logstash-config.yaml
- **Kibana Dashboards**: Modify dashboard creation script in kibana-dashboard-config.yaml
