environment          = "prod"
project              = "churn-mlops"
region               = "us-east-1"

cluster_version      = "1.34"

# t3.large for prod - Istio sidecars + full stack needs more RAM per node
node_instance_type   = "t3.large"
node_desired_count   = 3
node_min_count       = 3
node_max_count       = 10

# Full control plane logging in prod - api+audit+authenticator+scheduler+controller
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
