# resource "aws_elasticache_subnet_group" "this" {
#   name       = "redis-subnet-group"
#   subnet_ids = var.private_subnet_ids
# }

resource "aws_security_group" "redis" {
  name        = "redis-sg"
  description = "Redis access security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.default_tags
}
