locals {
  name        = var.name
  deploy_id   = var.deploy_id != "" ? var.deploy_id : formatdate("YYYYMMDDhhmmss", timestamp())
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "compute-ansible-${var.region}-${var.environment}"

  instances = { for pair in setproduct(range(length(var.private_subnets)), range(var.instances_per_az)) :
    "node-${pair[0] + 1}-${pair[1] + 1}" => {
      subnet        = var.private_subnets[pair[0]]
      az_idx        = pair[0]
      instance_type = lookup(var.instance_type_overrides, tostring(pair[0]), var.instance_type)
    }
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023[0].id
}

# --- IAM ---

resource "aws_iam_role" "instance" {
  name = "${local.name}-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${local.name}-instance" })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
  tags = var.tags
}

# --- IAM: EC2 Discovery ---

resource "aws_iam_role_policy" "ec2_discovery" {
  name = "ec2-discovery"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
      Resource = "*"
    }]
  })
}

# --- Security Group ---

resource "aws_security_group" "nodes" {
  name        = "${local.name}-nodes"
  description = "Allow all intra-VPC traffic for compute-ansible instances"
  vpc_id      = var.vpc_id

  ingress {
    description = "All traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name}-nodes" })
}

# --- EC2 Instances (on-demand, distributed per AZ) ---

resource "aws_instance" "node" {
  for_each = local.instances

  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/user-data.sh", {
    deployment_code = var.deployment_code
  })

  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    instance_metadata_tags = "enabled"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name            = "${local.name}-${each.key}"
    DeployID        = local.deploy_id
    deployment_code = var.deployment_code
  })
}

# --- EBS Data Volumes ---

resource "aws_ebs_volume" "data" {
  for_each = local.instances

  availability_zone = aws_instance.node[each.key].availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(var.tags, {
    Name = "${local.name}-${each.key}-data"
  })
}

resource "aws_volume_attachment" "data" {
  for_each = local.instances

  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data[each.key].id
  instance_id = aws_instance.node[each.key].id
}

# --- Route 53 Private DNS ---

resource "aws_route53_zone" "mesh" {
  count = var.enable_dns ? 1 : 0
  name  = var.dns_zone_name

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, {
    Name = "${local.name}-dns"
  })
}

resource "aws_route53_record" "node" {
  for_each = var.enable_dns ? local.instances : {}

  zone_id = aws_route53_zone.mesh[0].zone_id
  name    = "${each.key}.${var.dns_zone_name}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.node[each.key].private_ip]
}

# --- S3 Bucket ---

resource "aws_s3_bucket" "mesh" {
  count  = var.enable_s3_bucket ? 1 : 0
  bucket = local.bucket_name

  tags = merge(var.tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "mesh" {
  count  = var.enable_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.mesh[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mesh" {
  count  = var.enable_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.mesh[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role_policy" "s3_access" {
  count = var.enable_s3_bucket ? 1 : 0
  name  = "s3-mesh-access"
  role  = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.mesh[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.mesh[0].arn}/*"
      }
    ]
  })
}
