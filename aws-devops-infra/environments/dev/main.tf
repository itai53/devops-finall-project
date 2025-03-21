# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags               = var.default_tags
  vpc_tags           = { Name = var.vpc_name }
  public_subnet_tags = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
}
# ─────────────────────────────────────────────
# EKS Cluster
# ─────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.3"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"
  subnet_ids      = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  eks_managed_node_group_defaults = {
    instance_types = ["t4g.medium"]
    ami_type       = "AL2_ARM_64"
  }

  eks_managed_node_groups = {
    statuspage_app_nodes = {
      desired_size = 1
      min_size     = 1
      max_size     = 1
    }
  }
  enable_cluster_creator_admin_permissions = true
  tags = var.default_tags
}
module "eks_aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "20.8.3"
  manage_aws_auth_configmap = true
  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::992382545251:user/itaimoshe"
      username = "itaimoshe"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::992382545251:user/eladsopher"
      username = "eladsopher"
      groups   = ["system:masters"]
    }
  ]
  providers = {
    kubernetes = kubernetes
  }
  depends_on = [module.eks]
}
# ─────────────────────────────────────────────
# ALB Controller Setup (IRSA, SA, Helm)
# ─────────────────────────────────────────────
module "alb_irsa" {
  source       = "../../modules/alb_irsa"
  cluster_name = var.cluster_name
}
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_irsa.alb_controller_role_arn
    }
  }
  depends_on = [module.eks]
}
resource "helm_release" "aws_alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1"
  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  depends_on = [
    module.eks
  ]
}
# ─────────────────────────────────────────────
# RDS PostgreSQL
# ─────────────────────────────────────────────
module "rds_infra" {
  source             = "../../modules/rds"
  name_prefix = "statuspage-db"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  default_tags       = var.default_tags
}
module "rds_postgres" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.3.1"

  identifier = var.rds_identifier
  engine     = "postgres"
  engine_version = "15.12"
  instance_class = var.rds_instance_class
  allocated_storage = 20

  db_name  = var.rds_db_name
  username = var.rds_db_username
  password = var.rds_db_password
  port     = 5432

  vpc_security_group_ids = [module.rds_infra.rds_security_group_id]
  db_subnet_group_name   = module.rds_infra.rds_subnet_group

  multi_az               = false
  publicly_accessible    = false
  skip_final_snapshot    = true
  family = "postgres15"
  tags = var.default_tags
}
# ─────────────────────────────────────────────
# Redis (ElastiCache)
# ─────────────────────────────────────────────
module "redis_infra" {
  source              = "../../modules/redis"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnets
  default_tags        = var.default_tags
}
module "redis_registry" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.4.1"

  replication_group_id = var.replication_group_id 
  cluster_id           = var.redis_cluster_name
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_ids             = module.vpc.private_subnets
  security_group_ids     = [module.redis_infra.redis_security_group_id]

  tags = var.default_tags
}
# ─────────────────────────────────────────────
# Secrets Manager
# ─────────────────────────────────────────────
module "secrets_manager" {
  source        = "../../modules/secrets-manager"
  secret_name   = "${var.rds_db_name}-credentials"
  secret_data = {
    username = var.rds_db_username
    password = var.rds_db_password
    db_name  = var.rds_db_name
  }
  tags = var.default_tags
}
module "secret_opensearch_credentials" {
  source      = "../../modules/secrets-manager"
  secret_name = "opensearch-credentials"
  secret_data = {
    username = var.opensearch_admin_user
    password = var.opensearch_admin_password
  }
  tags = var.default_tags
}
module "secret_prometheus_remote_write" {
  source      = "../../modules/secrets-manager"
  secret_name = "prometheus-secret-for-cloud"
  secret_data = {
    username = var.prometheus_remote_username
    password = var.prometheus_remote_password
    url      = var.prometheus_remote_url
  }
  tags = var.default_tags
}
# ─────────────────────────────────────────────
# Route53 + ACM (SSL)
# ─────────────────────────────────────────────
#Route53
module "route53" {
  source       = "../../modules/route53"
  domain_name  = var.domain_name
  app_record_name = "app"
  tags         = var.default_tags
}
#ACM
module "acm" {
  source      = "../../modules/acm"
  domain_name = var.domain_name
  zone_id     = module.route53.zone_id
  tags        = var.default_tags
}
# ─────────────────────────────────────────────
# ECR Repository
# ─────────────────────────────────────────────
module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "${var.project_name}-ecr"
  tags            = var.default_tags
}

# Pass ECR repository URL to Helm values
locals {
  app_image_repo = module.ecr.repository_url
}

# ─────────────────────────────────────────────
# OpenSearch
# ─────────────────────────────────────────────
module "opensearch" {
  source  = "terraform-aws-modules/opensearch/aws"
  version = "1.6.0"

  domain_name    = var.opensearch_domain_name
  engine_version = "OpenSearch_1.3"

  cluster_config = {
    instance_type  = "r6g.large.search"
    instance_count = 1
  }

  ebs_options = {
    volume_size = var.ebs_volume_size
    volume_type = "gp3"
  }
  advanced_security_options = {
    enabled                         = true
    internal_user_database_enabled = true
    master_user_options = {
      master_user_name     = var.opensearch_admin_user
      master_user_password = var.opensearch_admin_password
    }
  }
  tags = var.default_tags
}
# ─────────────────────────────────────────────
# External Secrets Operator
# ─────────────────────────────────────────────
resource "helm_release" "external_secrets_operator" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.9.10"
  values = []
  depends_on = [module.eks]
}
# ─────────────────────────────────────────────
# External DNS (IRSA + Helm)
# ─────────────────────────────────────────────
module "external_dns_irsa" {
  source                     = "../../modules/external_dns_irsa"
  cluster_name               = var.cluster_name
  cluster_oidc_issuer_url    = module.eks.cluster_oidc_issuer_url
  default_tags            = var.default_tags
}
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.14.4"
  namespace  = "external-dns"
  create_namespace = true
  values = [
    file("${path.module}/../../externaldns/values.yaml")
  ]
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_dns_irsa.externaldns_role_arn
  }
  depends_on = [module.eks]
}
# ─────────────────────────────────────────────
# Fluent Bit (Centralized Logging)
# ─────────────────────────────────────────────
resource "helm_release" "fluentbit" {
  name             = "fluentbit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = "0.46.3"
  namespace        = "logging"
  create_namespace = true

  values = [
    file("${path.module}/../../fluentbit/values.yaml")
  ]
  # Dynamically inject OpenSearch output config
set {
  name  = "extraOutputPlugin"
  value = <<EOT
[OUTPUT]
    Name  es
    Match *
    Host  ${module.opensearch.domain_endpoint}
    Port  443
    Index fluentbit
    Type  _doc
    Logstash_Format On
    Retry_Limit False
    tls On
    HTTP_User admin
    HTTP_Passwd ${var.opensearch_admin_password}
EOT
}
  depends_on = [
    module.eks,
    module.opensearch
  ]
}
# ─────────────────────────────────────────────
# Prometheus Monitoring Stack
# ─────────────────────────────────────────────
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "56.6.0" # You can use latest or pin it
  namespace        = "monitoring"
  create_namespace = true
  values = [
    file("${path.module}/../../prometheus/values.yaml") 
  ]
  depends_on = [module.eks]
}
# ─────────────────────────────────────────────
# StatusPage App Deployment (via Helm Chart)
# ─────────────────────────────────────────────
resource "helm_release" "statuspage_app" {
  name             = "statuspage"
  chart            = "${path.module}/../../statuspage"
  namespace        = "default"
  create_namespace = true
  set {
    name  = "image.repository"
    value = local.app_image_repo
  }
  set {
    name  = "ingress.enabled"
    value = "true"
  }
  set {
    name  = "ingress.name"
    value = "statuspage-ingress"
  }
  set {
    name  = "ingress.namespace"
    value = "default"
  }
  set {
    name  = "ingress.scheme"
    value = "internet-facing"
  }
  set {
    name  = "ingress.targetType"
    value = "ip"
  }
  set {
    name  = "ingress.listenPorts"
    value = "[{\"HTTP\":80}]"
  }
  set {
    name  = "ingress.loadBalancerName"
    value = "my-statuspage-alb"
  }
  set {
    name  = "ingress.externalDnsHostname"
    value = "app.imlinfo.xyz"
  }
  set {
    name  = "ingress.className"
    value = "alb"
  }
  set {
    name  = "ingress.host"
    value = "app.imlinfo.xyz"
  }
  set {
    name  = "ingress.serviceName"
    value = "statuspage-service"
  }
  set {
    name  = "ingress.servicePort"
    value = "80"
  }
  depends_on = [
    module.eks,
    helm_release.aws_alb_controller
  ]
}
resource "helm_release" "helm_test_nginx" {
  name             = "nginx-test"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "nginx"
  version          = "15.12.1"   # ← SPECIFY THIS! Important
  namespace        = "default"
  create_namespace = true
}
