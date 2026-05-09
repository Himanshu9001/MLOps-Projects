environment          = "nonprod"
project              = "churn-mlops"
region               = "us-east-1"

cluster_version      = "1.34"
node_instance_type   = "t3.medium"
node_desired_count   = 3
node_min_count       = 2
node_max_count       = 6

enabled_cluster_log_types = ["api", "audit", "authenticator"]
