/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "gcp_project" {
  description = "Name of the Google Cloud project to deploy to"
}

variable "gcp_region" {
  description = "GCP region to create resources in"
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone to create resources in"
  default     = "us-central1-f"
}

variable "infrastructure_id" {
  description = "Unique identifier for the deployment"
}

variable "container_base_image" {
  description = "Base GCP container image"
  default = "cos-cloud/cos-stable"
}

variable "prometheus_server_docker_image" {
  description = "Prometheus server docker image"
  default = "prom/prometheus:latest"
}

variable "prometheus_server_machine_type" {
  description = "Machine type for Prometheus server"
  default     = "n1-standard-2"
}

variable "prometheus_server_disk_size_gb" {
  description = "Disk size for Prometheus server machine."
  default     = 100
}

variable "grafana_server_docker_image" {
  description = "Grafana server docker image"
  default = "grafana/grafana:latest"
}

variable "grafana_server_machine_type" {
  description = "Machine type for Grafana server"
  default     = "n1-standard-2"
}

variable "grafana_server_disk_size_gb" {
  description = "Disk size for Grafana server machine."
  default     = 100
}

variable "vpc_network" {
  description = "The VPC network the stack will be configured in"
  default = "default"
}

variable "monitoring_admin_username" {
  description = "Monitoring admin user"
  default     = "admin"
}
