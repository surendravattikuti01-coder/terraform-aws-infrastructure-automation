# ============================================================
# Production Environment Root Module
# Composes: VPC + EKS + IAM + RDS + ElastiCache modules
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes"; version = "~> 2.23" }
    helm = { source = "hashicorp/helm"; version = "~> 2.11" }
  }

  backend "s3" {
    # Configured via -backend-config in CI/CD pipeline
    # bucket         = "tfstate-prod"
    # key            = "prod/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "terraform-lock-prod"
    # encrypt        = true
    # kms_key_id     = "arn:aws:kms:us-east-1:123456789012:key/..."
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = "platform-engineering"
      CostCenter  = "prod-infra"
    }
  }

  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/terraform-prod-role"
    session_name = "terraform-prod-session"
  }
}

# ─── Data Sources ─────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ─── VPC Module ───────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project_name          = var.project_name
  environment           = "prod"
  vpc_cidr              = var.vpc_cidr
  availability_zones    = slice(data.aws_availability_zones.available.names, 0, 3)
  enable_nat_gateway_ha = true   # One NAT GW per AZ for HA
  enable_flow_logs      = true
  enable_vpc_endpoints  = true

  tags = var.common_tags
}

# ─── EKS Module ───────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  project_name            = var.project_name
  environment             = "prod"
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  kubernetes_version      = "1.28"
  enable_public_endpoint  = false  # Private cluster only in prod
  public_access_cidrs     = []

  node_groups = {
    system = {
      instance_types  = ["m5.large"]
      ami_type        = "AL2_x86_64"
      capacity_type   = "ON_DEMAND"
      disk_size       = 50
      desired_size    = 3
      min_size        = 3
      max_size        = 6
      labels          = { "node-role" = "system" }
      taints          = [{ key = "CriticalAddonsOnly"; value = "true"; effect = "NO_SCHEDULE" }]
    }
    application = {
      instance_types  = ["m5.2xlarge", "m5.4xlarge"]
      ami_type        = "AL2_x86_64"
      capacity_type   = "SPOT"
      disk_size       = 100
      desired_size    = 5
      min_size        = 3
      max_size        = 50
      labels          = { "node-role" = "application" }
      taints          = []
    }
    gpu = {
      instance_types  = ["g4dn.xlarge"]
      ami_type        = "AL2_x86_64_GPU"
      capacity_type   = "ON_DEMAND"
      disk_size       = 100
      desired_size    = 0
      min_size        = 0
      max_size        = 5
      labels          = { "node-role" = "gpu"; "nvidia.com/gpu" = "true" }
      taints          = [{ key = "nvidia.com/gpu"; value = "true"; effect = "NO_SCHEDULE" }]
    }
  }

  tags = var.common_tags
  depends_on = [module.vpc]
}

# ─── Kubernetes Provider (post-EKS) ───────────────────────
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# ─── Outputs ──────────────────────────────────────────────
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "Production VPC ID"
}

output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "EKS cluster name"
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "EKS API server endpoint"
  sensitive   = true
}

output "eks_oidc_issuer" {
  value       = module.eks.oidc_issuer_url
  description = "EKS OIDC issuer URL for IRSA"
}
