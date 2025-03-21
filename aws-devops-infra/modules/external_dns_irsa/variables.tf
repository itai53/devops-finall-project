variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  type        = string
}

variable "default_tags" {
  description = "Default tags"
  type        = map(string)
}