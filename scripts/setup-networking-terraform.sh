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
# Step 6 — Install StorageClass for Airflow
# SKIPPED — EBS CSI addon already installed by Terraform
# Just create the StorageClass
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
# ─────────────────────────────────────────
echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/install.yaml

echo "Waiting for ArgoCD server..."
kubectl wait --for=condition=available deployment \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=120s
echo "ArgoCD installed!"

# ─────────────────────────────────────────
# Step 9 — Install Argo Rollouts
# ─────────────────────────────────────────
echo "Installing Argo Rollouts..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
echo "Argo Rollouts installed!"

# ─────────────────────────────────────────
# Step 10 — Install Istio
# ─────────────────────────────────────────
echo "Installing Istio..."
if ! command -v istioctl &> /dev/null; then
  echo "istioctl not found. Install with:"
  echo "  curl -L https://istio.io/downloadIstio | sh -"
  echo "  export PATH=\$PATH:\$HOME/.istioctl/bin"
  echo "Skipping Istio install - run manually"
else
  istioctl install --set profile=default -y
  echo "Istio installed!"
fi

# ─────────────────────────────────────────
# Step 11 — Deploy Helm chart (churn-mlops)
# Run AFTER Argo Rollouts + Istio are ready
# ─────────────────────────────────────────
echo "Deploying churn-mlops Helm chart..."
helm upgrade --install churn-mlops helm/churn-mlops/ \
  --values helm/churn-mlops/values.yaml \
  --wait \
  --timeout 5m
echo "churn-mlops deployed!"

# ─────────────────────────────────────────
# Step 12 — Bootstrap ArgoCD App of Apps
# ─────────────────────────────────────────
echo "Bootstrapping ArgoCD App of Apps..."
kubectl apply -f argocd/app-of-apps.yaml
echo "ArgoCD App of Apps bootstrapped!"

# ─────────────────────────────────────────
# Step 13 — Apply ServiceMonitor
# ─────────────────────────────────────────
echo "Applying ServiceMonitor..."
kubectl apply -f k8s/servicemonitor.yaml
echo "ServiceMonitor applied!"

echo ""
echo "Setup complete!"
echo ""
echo "Access commands:"
echo "  ArgoCD UI:  kubectl port-forward svc/argocd-server -n argocd 8081:443"
echo "  ArgoCD pwd: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "  Airflow UI: kubectl port-forward svc/airflow-api-server -n airflow 8080:8080"
echo "  Grafana UI: kubectl get svc -n monitoring | grep grafana"
echo ""
echo "Next steps:"
echo "  1. Get new ALB URL: kubectl get svc -n churn-mlops"
echo "  2. Update k8s/stream-processor-deployment.yaml API_URL with new ALB"
echo "  3. git push -> ArgoCD auto-syncs stream processor"
