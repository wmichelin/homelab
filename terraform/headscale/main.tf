terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

# Domain zone is owned by Pantry terraform. Homelab only manages the hs record.
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "droplet_ip" {
  description = "Public IPv4 of the shared pantry droplet (terraform output droplet_ip there)"
  type        = string
}

resource "digitalocean_record" "hs" {
  domain = "waltermichelin.com"
  type   = "A"
  name   = "hs"
  value  = var.droplet_ip
  ttl    = 300
}

output "headscale_url" {
  value = "https://hs.waltermichelin.com"
}

output "hs_record" {
  value = "hs.waltermichelin.com → ${var.droplet_ip}"
}
