variable "subnets" {
  type    = list(string)
  default = ["subnet-0a97a8d88b458ebb6", "subnet-07c70c1cc9b65ec28"]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"

  cluster_name    = "eks-cluster"
  cluster_version = "1.29"

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id                   = "vpc-08522c13570457b27"
  subnet_ids               = ["subnet-0a97a8d88b458ebb6", "subnet-07c70c1cc9b65ec28"]
  control_plane_subnet_ids = ["subnet-0a97a8d88b458ebb6", "subnet-07c70c1cc9b65ec28"]
 # Self Managed Node Group(s)
  self_managed_node_group_defaults = {
    instance_type                          = "r5.xlarge"
    update_launch_template_default_version = true
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws-us-gov:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  cluster_security_group_additional_rules = {
    ingress_ec2_tcp = {
      description                = "Additional Access"
      protocol                   = "all"
      from_port         = 0
      to_port           = 65535
      type                       = "ingress"
      cidr_blocks      = ["10.0.0.0/16"]
      source_cluster_security_group = false
    }
  }

  eks_managed_node_groups = {
    irs-cluster-wg = {
      min_size     = 1
      max_size     = 6
      desired_size = 2

      instance_types = ["r5.xlarge"]
      capacity_type  = "ON_DEMAND"
    }
  }
  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_group_defaults = {
    ami_type              = "BOTTLEROCKET_x86_64"
    platform              = "bottlerocket"
    instance_types        = [ "r5.xlarge" ]

    # Force gp3 & encryption (https://github.com/bottlerocket-os/bottlerocket#default-volumes)
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs         = {
          volume_size           = 20
          volume_type           = "gp3"
          iops                  = 3000
          #throughput            = 150
          encrypted             = true
          delete_on_termination = true
        }
      },
      xvdb = {
        device_name = "/dev/xvdb"
        ebs         = {
          volume_size           = 1000
          volume_type           = "gp3"
          iops                  = 3000
          #throughput            = 150
          encrypted             = true
          delete_on_termination = true
        }
      }
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
  
}

resource "aws_security_group" "efs" {
  name        = "bmf-efs"
  description = "Allow traffic"
  vpc_id      = "vpc-08522c13570457b27"

  ingress {
    description      = "nfs"
    from_port        = 2049
    to_port          = 2049
    protocol         = "TCP"
    cidr_blocks      = ["10.0.0.0/16"]
  }
}

resource "aws_iam_policy" "node_efs_policy" {
  name        = "eks_node_efs-policy"
  path        = "/"
  description = "Policy for EFKS nodes to use EFS"

  policy = jsonencode({
    "Statement": [
        {
            "Action": [
                "elasticfilesystem:DescribeMountTargets",
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeAccessPoints",
                "elasticfilesystem:CreateAccessPoint",
                "elasticfilesystem:DeleteAccessPoint",
                "ec2:DescribeAvailabilityZones"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "efspolicy"
        }
    ],
    "Version": "2012-10-17"
}
  )
}

resource "aws_efs_file_system" "kube" {
  creation_token = "eks-efs"
}

resource "aws_efs_mount_target" "mount" {
    file_system_id = aws_efs_file_system.kube.id
    subnet_id = each.key
    for_each = toset(var.subnets)
    security_groups = [aws_security_group.efs.id]
}
