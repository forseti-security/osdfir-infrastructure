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



locals {
  # API services to enable for the project
  services_list = [
    "compute.googleapis.com"
  ]
}

resource "google_project_service" "services" {
  count              = length(local.services_list)
  project            = var.gcp_project
  service            = local.services_list[count.index]
  disable_on_destroy = false
}

#-----------------------#
# Prometheus            #
#-----------------------#
data "template_file" "prometheus-startup-script" {
  template = file("${path.module}/templates/scripts/install-prometheus.sh.tpl")

  vars = {
    project       = var.gcp_project
    zone          = var.gcp_zone
  }
}

resource "google_compute_instance" "prometheus" {
  name         = "prometheus-server-${var.infrastructure_id}"
  machine_type = var.prometheus_server_machine_type
  zone         = var.gcp_zone
  depends_on   = [google_project_service.services]


  # Allow to stop/start the machine to enable change machine type.
  allow_stopping_for_update = true

  # Use default Ubuntu image as operating system.
  boot_disk {
    initialize_params {
      image = var.container_base_image
      size  = var.prometheus_server_disk_size_gb
    }
  }

  # Assign a generated public IP address. Needed for SSH access.
  network_interface {
    network       = var.vpc_network
    access_config {}
  }

  # Tag for service enumeration.
  labels = {
    "turbinia-prometheus" = "true"
  }

  # Enable the GCE discovery module to call required APIs.
  service_account {
    scopes = ["compute-ro"]
  }

  # Provision the machine with a script.
  metadata_startup_script = data.template_file.prometheus-startup-script.rendered
}


#-----------------------#
# Grafana               #
#-----------------------#
data "template_file" "grafana-startup-script" {
  template = file("${path.module}/templates/scripts/install-grafana.sh.tpl")

  vars = {
    project       = var.gcp_project
    zone          = var.gcp_zone
  }
}

resource "google_compute_instance" "grafana" {
  name         = "grafana-server-${var.infrastructure_id}"
  machine_type = var.grafana_server_machine_type
  zone         = var.gcp_zone
  depends_on   = [google_project_service.services]


  # Allow to stop/start the machine to enable change machine type.
  allow_stopping_for_update = true

  # Use default Ubuntu image as operating system.
  boot_disk {
    initialize_params {
      image = var.container_base_image
      size  = var.grafana_server_disk_size_gb
    }
  }

  # Assign a generated public IP address. Needed for SSH access.
  network_interface {
    network       = var.vpc_network
    access_config {}
  }

  # Tag for service enumeration.
  labels = {
    "turbinia-prometheus" = "true"
  }

  # Enable the GCE discovery module to call required APIs.
  service_account {
    scopes = ["compute-ro"]
  }

  # Provision the machine with a script.
  metadata_startup_script = data.template_file.install-grafana-script.rendered
}