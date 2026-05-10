#!/bin/bash
set -e

echo "Setting up application stack on Terraform-managed cluster..."

# ─────────────────────────────────────────
# Configuration — new Terraform cluster
# ─────────────────────────────────────────
REGION="us-east-1"
CLUSTER_NAME="churn-mlops-nonprod"

# SKIPPED — handled by Terraform:
#   - VPC creation (10-network stack)
#   - Subnets, IGW, NAT Gateway, route tables (10-network stack)
#   - Security groups (10-network stack)
#   - VPC peering (not needed — EKS shares nonprod VPC)
#   - OIDC association (40-kubernetes stack)
#   - IRSA trust policy update (30-compute stack)
#   - VPC CNI network policy controller (40-kubernetes addon config)
#   - EBS CSI driver (40-kubernetes stack)
#   - S3 policy on node role (iam module — IRSA used instead)
#   - kubeconfig update (done manually)

# ─────────────────────────────────────────
# Step 1 — Verify correct cluster
# ─────────────────────────────────────────
echo "Verifying cluster context..."
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"

if [[ "$CURRENT_CONTEXT" != *"churn-mlops-nonprod"* ]]; then
  echo "ERROR: Wrong cluster context. Expected churn-mlops-nonprod."
  echo "Run: aws eks update-kubeconfig --name churn-mlops-nonprod --region us-east-1"
  exit 1
fi
echo "Cluster context verified!"

# ─────────────────────────────────────────
# Step 2 — Install Secrets Store CSI Driver
# ─────────────────────────────────────────
echo "Installing Secrets Store CSI Driver..."
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts 2>/dev/null || true
helm repo update

helm upgrade --install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --wait

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

kubectl patch csidriver secrets-store.csi.k8s.io \
  --type=merge \
  -p '{"spec":{"tokenRequests":[{"audience":"sts.amazonaws.com"}]}}'
echo "Secrets Store CSI Driver installed!"

# ─────────────────────────────────────────
# Step 3 — Install OPA Gatekeeper
# ─────────────────────────────────────────
echo "Installing OPA Gatekeeper..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>/dev/null || true
helm repo update

helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --wait \
  --timeout 5m

kubectl apply -f k8s/gatekeeper/constraint-templates.yaml
kubectl wait --for=condition=established \
  crd/k8snoroot.constraints.gatekeeper.sh \
  crd/k8srequirelimits.constraints.gatekeeper.sh \
  crd/k8snoprivileged.constraints.gatekeeper.sh \
  --timeout=60s
kubectl apply -f k8s/gatekeeper/constraints.yaml
echo "OPA Gatekeeper installed!"

# ─────────────────────────────────────────
# Step 4 — Install Kafka (Strimzi)
# ─────────────────────────────────────────
echo "Installing Kafka via Strimzi..."
helm repo add strimzi https://strimzi.io/charts/ 2>/dev/null || true
helm repo update

helm upgrade --install strimzi strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace \
  --wait \
  --timeout 5m

echo "Waiting for Strimzi CRDs..."
kubectl wait --for=condition=established \
  crd/kafkas.kafka.strimzi.io \
  --timeout=60s

kubectl apply -f k8s/kafka/kafka-cluster.yaml
kubectl wait kafka/churn-kafka \
  --for=condition=Ready \
  --timeout=5m \
  -n kafka

kubectl apply -f k8s/kafka/kafka-topics.yaml
echo "Kafka installed!"

# ─────────────────────────────────────────
# Step 5 — Install Prometheus + Grafana
# ─────────────────────────────────────────
echo "Installing Prometheus + Grafana..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/monitoring/values.yaml \
  --wait \
  --timeout 10m
echo "Prometheus + Grafana installed!"

# ─────────────────────────────────────────
# Step 6 — Create EBS StorageClass
# EBS CSI addon already installed by Terraform
# ─────────────────────────────────────────
echo "Creating EBS StorageClass..."
kubectl apply -f - << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate
parameters:
  type: gp2
EOF
echo "StorageClass created!"

# ─────────────────────────────────────────
# Step 7 — Install Airflow
# ─────────────────────────────────────────
echo "Installing Airflow..."
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update

kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --set executor=KubernetesExecutor \
  --set webserver.defaultUser.enabled=true \
  --set webserver.defaultUser.username=admin \
  --set webserver.defaultUser.password=admin123 \
  --set webserver.defaultUser.email=admin@example.com \
  --set webserver.defaultUser.firstName=Admin \
  --set webserver.defaultUser.lastName=User \
  --set webserver.defaultUser.role=Admin \
  --set dags.persistence.enabled=false \
  --set dags.gitSync.enabled=true \
  --set dags.gitSync.repo=https://github.com/Himanshu9001/MLOps-Projects.git \
  --set dags.gitSync.branch=main \
  --set dags.gitSync.subPath=dags \
  --set dags.gitSync.wait=60 \
  --set postgresql.primary.persistence.storageClass=ebs-sc \
  --set triggerer.persistence.storageClassName=ebs-sc \
  --timeout 10m

kubectl apply -f - << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: airflow-pod-launcher
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: airflow-pod-launcher-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: airflow-pod-launcher
subjects:
  - kind: ServiceAccount
    name: airflow-scheduler
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-worker
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-triggerer
    namespace: airflow
EOF
echo "Airflow installed!"

# ─────────────────────────────────────────
# Step 8 — Install ArgoCD
# FIXED: pinned to v2.14.9 (stable tag returns 404)
# ─────────────────────────────────────────
echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.9/manifests/install.yaml

echo "Waiting for ArgoCD server..."
kubectl wait --for=condition=available deployment \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=120s
echo "ArgoCD installed!"

# ─────────────────────────────────────────
# Step 9 — Install Argo Rollouts
# FIXED: pinned to v1.8.3 (latest tag unpredictable)
# ─────────────────────────────────────────
echo "Installing Argo Rollouts..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/download/v1.8.3/install.yaml
echo "Argo Rollouts installed!"

# ─────────────────────────────────────────
# Step 10 — Install Istio
# Requires istioctl installed on your machine:
#   brew install istioctl
# ─────────────────────────────────────────
echo "Installing Istio..."
if ! command -v istioctl &> /dev/null; then
  echo "istioctl not found. Install with: brew install istioctl"
  echo "Skipping Istio - run manually after install"
else
  istioctl install --set profile=default -y
  kubectl label namespace churn-mlops istio-injection=enabled --overwrite 2>/dev/null || true
  echo "Istio installed!"
fi

# ─────────────────────────────────────────
# Step 11 — Deploy Helm chart
# Runs AFTER Argo Rollouts + Istio are ready
# ─────────────────────────────────────────
echo "Deploying churn-mlops Helm chart..."
kubectl label namespace churn-mlops istio-injection=enabled \
  --overwrite 2>/dev/null || true

# Delete Istio resources owned by Argo Rollouts controller to avoid
# ServerSideApply field ownership conflict on helm upgrade.
# Argo Rollouts owns .spec.subsets on DestinationRule — Helm cannot
# upgrade this field while Argo Rollouts is also managing it.
kubectl delete destinationrule churn-prediction-api-destrule -n churn-mlops 2>/dev/null || true
kubectl delete virtualservice churn-prediction-api-vsvc -n churn-mlops 2>/dev/null || true

helm upgrade --install churn-mlops helm/churn-mlops/ -n churn-mlops \
  --values helm/churn-mlops/values.yaml \
  --timeout 5m
echo "churn-mlops deployed!"

# ─────────────────────────────────────────
# Step 12 — Bootstrap ArgoCD App of Apps
# ─────────────────────────────────────────
echo "Bootstrapping ArgoCD App of Apps..."
kubectl apply -f argocd/app-of-apps.yaml

# Apply Image Updater configmap and CR
echo "Applying ArgoCD Image Updater configmap..."
kubectl apply -f argocd/image-updater-configmap.yaml
echo "Applying ArgoCD Image Updater CR..."
kubectl apply -f argocd/image-updater.yaml
echo "ArgoCD App of Apps bootstrapped!"

# ─────────────────────────────────────────
# Step 13 — Apply ServiceMonitor
# ─────────────────────────────────────────
echo "Applying ServiceMonitor..."
kubectl apply -f k8s/servicemonitor.yaml
echo "ServiceMonitor applied!"

# ─────────────────────────────────────────
# Step 14 — Migrate MLflow model
# REQUIRED — new RDS is always empty after rebuild
# ─────────────────────────────────────────
echo ""
echo "IMPORTANT: MLflow model migration required!"
echo "New RDS is empty. Run the following to migrate the model:"
echo ""
echo "  # Upload migration script"
echo "  aws s3 cp scripts/migrate-mlflow-model.py s3://churn-mlops-nonprod-artifacts/scripts/"
echo ""
echo "  # Get new EC2 instance ID"
echo "  terraform -chdir=terraform/live/nonprod/30-compute/stacks output mlflow_instance_id"
echo ""
echo "  # Connect and run migration"
echo "  aws ssm start-session --target <INSTANCE_ID> --region us-east-1"
echo "  # Inside EC2:"
echo "  #   aws s3 cp s3://churn-mlops-nonprod-artifacts/scripts/migrate-mlflow-model.py /tmp/"
echo "  #   pip3 install mlflow boto3 --user --quiet"
echo "  #   python3 /tmp/migrate-mlflow-model.py"
echo ""
echo "Setup complete!"
echo ""
echo "Access commands:"
echo "  ArgoCD UI:  kubectl port-forward svc/argocd-server -n argocd 8081:443"
echo "  ArgoCD pwd: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "  Airflow UI: kubectl port-forward svc/airflow-api-server -n airflow 8080:8080"
echo "  Grafana UI: kubectl get svc -n monitoring | grep grafana"
echo "  ALB URL:    kubectl get svc -n churn-mlops"

# ─────────────────────────────────────────
# Step 15 — Create ECR credentials for Image Updater
# ECR token expires every 12 hours - refresh manually or via CronJob
# ─────────────────────────────────────────
echo "Creating ECR credentials for Image Updater..."
AWS_ACCOUNT=011528270076
REGION=us-east-1
ECR_TOKEN=$(aws ecr get-authorization-token \
  --region $REGION \
  --query 'authorizationData[0].authorizationToken' \
  --output text | base64 -d | cut -d: -f2)

kubectl create secret docker-registry ecr-creds \
  --docker-server=${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password=${ECR_TOKEN} \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -
echo "ECR credentials created (valid for 12 hours)!"

# ─────────────────────────────────────────
# Step 16 — Install Karpenter
# Provisions right-sized nodes on demand for Ray workloads
# Coexists with Cluster Autoscaler (manages separate node sets)
# Prerequisites:
#   - SQS queue must exist: churn-mlops-nonprod
#   - IAM role must exist: churn-mlops-nonprod-karpenter-role
#   - Subnets tagged: karpenter.sh/discovery=churn-mlops-nonprod
#   - Security groups tagged: karpenter.sh/discovery=churn-mlops-nonprod
# ─────────────────────────────────────────
echo "Installing Karpenter..."
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  --namespace karpenter \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::011528270076:role/churn-mlops-nonprod-karpenter-role \
  --set settings.clusterName=churn-mlops-nonprod \
  --set settings.interruptionQueue=churn-mlops-nonprod \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.limits.cpu=500m \
  --set controller.resources.limits.memory=512Mi \
  --wait \
  --timeout 5m

kubectl apply -f k8s/karpenter/ec2nodeclass.yaml
kubectl apply -f k8s/karpenter/nodepool.yaml
echo "Karpenter installed!"

# ─────────────────────────────────────────
# Step 17 — Install KubeRay Operator
# Manages RayCluster, RayJob, RayService CRDs
# Ray cluster itself is managed by ArgoCD (k8s/ray/)
# ─────────────────────────────────────────
echo "Installing KubeRay operator..."
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ 2>/dev/null || true
helm repo update

helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace \
  --version 1.2.2 \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=512Mi \
  --wait \
  --timeout 5m

# Create Ray IRSA ServiceAccount
kubectl apply -f - << \'RAYSA\'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ray-worker-sa
  namespace: ray-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::011528270076:role/churn-mlops-nonprod-irsa-role
\'RAYSA\'
echo "KubeRay operator installed!"
