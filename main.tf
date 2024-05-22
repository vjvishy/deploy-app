data "terraform_remote_state" "eks-cluster" {
  backend = "local"
 
  config = {
    path = "../eks-cluster/terraform.tfstate"
  }
}

data "terraform_remote_state" "mongodb" {
  backend = "local"
 
  config = {
    path = "../mongodb/terraform.tfstate"
  }
}

# Get EKS cluster Region
provider "aws" {
  region = data.terraform_remote_state.eks-cluster.outputs.region
}

# Get EKS cluster name
data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.eks-cluster.outputs.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.aws_eks_cluster.cluster.name
    ]
  }
}

resource "kubernetes_env" "example" {
  container = "tasky"
  metadata {
    name = "tasky"
  }

  api_version = "apps/v1"
  kind        = "Deployment"

  env {
    name  = "MONGODB_URI"
    value = "mongodb://${data.terraform_remote_state.mongodb.outputs.mongodb_username}:${data.terraform_remote_state.mongodb.outputs.mongodb_password}@${data.terraform_remote_state.mongodb.outputs.ec2_instance_dns_name}:27017"
  }

  env {
    name  = "SECRET_KEY"
    value = "secret123"
  }
}

resource "kubernetes_deployment" "tasky" {
  metadata {
    name = "tasky"
    labels = {
      App = "tasky-app"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        App = "tasky-app"
      }
    }
    template {
      metadata {
        labels = {
          App = "tasky-app"
        }
      }
      spec {
        container {
          image = "ghcr.io/vjvishy/tasky:latest"
          name  = "tasky"

          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "tasky" {
  metadata {
    name = "tasky"
  }
  spec {
    selector = {
      App = kubernetes_deployment.tasky.spec.0.template.0.metadata[0].labels.App
    }
    port {
      port        = 8080
      target_port = 8080
    }
 
    type = "LoadBalancer"
  }
}

output "lb_ip" {
  value = kubernetes_service.tasky.status.0.load_balancer.0.ingress.0.hostname
}
