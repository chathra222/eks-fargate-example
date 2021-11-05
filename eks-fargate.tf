provider "aws" {
  region = local.region
}

locals {
  name            = "eks-fargate-chathra"
  cluster_version = "1.20"
  region          = "ap-southeast-1"
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  vpc_id          = module.vpc.vpc_id
  subnets         = [module.vpc.private_subnets[0], module.vpc.public_subnets[1]]
  fargate_subnets = [module.vpc.private_subnets[2]]

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # You require a node group to schedule coredns which is critical for running correctly internal DNS.
  # If you want to use only fargate you must follow docs `(Optional) Update CoreDNS`
  # available under https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html
  node_groups = {
    example = {
      desired_capacity = 1

      instance_types = ["t3.large"]
      k8s_labels = {
        Example    = "managed_node_groups"
        GithubRepo = "terraform-aws-eks"
        GithubOrg  = "terraform-aws-modules"
      }
      additional_tags = {
        ExtraTag = "example"
      }
      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }
    }
  }

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "default"
          labels = {
            WorkerType = "fargate"
          }
        },

        {
          namespace = "dev"
          labels = {
            app = "webappinfargate"
          }
        }
      ]

      tags = {
        Owner = "default"
      }
    }

    secondary = {
      name = "secondary"
      selectors = [
        {
          namespace = "default"
          labels = {
            Environment = "test"
            GithubRepo  = "terraform-aws-eks"
            GithubOrg   = "terraform-aws-modules"
          }
        }
      ]

      # Using specific subnets instead of the ones configured in EKS (`subnets` and `fargate_subnets`)
      subnets = [module.vpc.private_subnets[1]]


      tags = {
        Owner = "secondary"
      }
    }

    # added fargate profile for coredns to run coredns in fargate https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html
    coredns = {
      name = "coredns"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        }
      ]

      # Using specific subnets instead of the ones configured in EKS (`subnets` and `fargate_subnets`)
      subnets = [module.vpc.private_subnets[0]]

      tags = {
        Owner = "secondary"
      }
    }
  }

  manage_aws_auth = false

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}


################################################################################
# Kubernetes provider configuration
################################################################################

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

################################################################################
# Supporting Resources
################################################################################

data "aws_availability_zones" "available" {
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "~> 3.0"
  name                 = local.name
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }
  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}
