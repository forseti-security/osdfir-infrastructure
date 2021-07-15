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

resource "random_string" "monitoring-admin-password" {
  length = 16
  special = false
}

#-----------------------#
# Prometheus            #
#-----------------------#
resource "google_compute_disk" "promd" {
  project = var.gcp_project
  name    = "prometheus-${var.infrastructure_id}-data-disk"
  type    = "pd-standard"
  zone    = var.gcp_zone
  size    = 1000
}

data "template_file" "prometheus-startup-script" {
  template = file("${path.module}/templates/scripts/install-prometheus.sh.tpl")

  vars = {
    project       = var.gcp_project
    zone          = var.gcp_zone
    prom-disk = "prometheus-${var.infrastructure_id}-data-disk"
  }
}

module "prometheus-container" {
  source = "terraform-google-modules/container-vm/google"

  container = {
    name    = "prometheus-container-${var.infrastructure_id}"
    image   = var.prometheus_server_docker_image
    volumeMounts = [
      {
        name: "prometheus-config"
        mountPath: "/etc/prometheus"
      }, {
        name: "prometheus-data"
        mountPath: "/prometheus"
      }
    ]

    tty : true
    stdin : true
  }

  restart_policy = "Always"

  volumes = [
    {
      name = "prometheus-config"
      hostPath = {path="/etc/prometheus"}
    }, {
      name = "prometheus-data"
      gcePersistentDisk = {
        pdName="prometheus-${var.infrastructure_id}-data-disk"
        fsType="ext4"
        }
    }
  ]
}

resource "google_compute_instance" "prometheus" {
  name         = "prometheus-server-${var.infrastructure_id}"
  machine_type = var.prometheus_server_machine_type
  zone         = var.gcp_zone
  depends_on   = [google_project_service.services]


  # Allow to stop/start the machine to enable change machine type.
  allow_stopping_for_update = true

  # Use container os image as operating system.
  boot_disk {
    initialize_params {
      image = var.container_base_image
      size  = var.prometheus_server_disk_size_gb
    }
  }

  attached_disk {
    source = google_compute_disk.promd.self_link
    device_name = "prometheus-${var.infrastructure_id}-data-disk"
    mode = "READ_WRITE"
  }

  # Assign a generated public IP address. Needed for SSH access.
  network_interface {
    network       = var.vpc_network
  }

  # Tag for service enumeration.
  labels = {
    "turbinia-prometheus" = "true"
  }

  # Enable the GCE discovery module to call required APIs.
  service_account {
    scopes = ["compute-ro"]
  }

  metadata = {
    gce-container-declaration = module.prometheus-container.metadata_value
    google-logging-enabled = "true"
    google-monitoring-enabled = "true"
  }

  # Provision the machine with a script.
  metadata_startup_script = data.template_file.prometheus-startup-script.rendered
}


#-----------------------#
# Grafana               #
#-----------------------#
resource "google_compute_disk" "grafd" {
  project = var.gcp_project
  name    = "grafana-${var.infrastructure_id}-data-disk"
  type    = "pd-standard"
  zone    = var.gcp_zone
  size    = 1000
}

data "template_file" "grafana-startup-script" {
  template = file("${path.module}/templates/scripts/install-grafana.sh.tpl")

  vars = {
    prometheus-server = "prometheus-server-${var.infrastructure_id}"
    grafana-disk = "grafana-${var.infrastructure_id}-data-disk"
  }
}


module "grafana-container" {
  source = "terraform-google-modules/container-vm/google"

  container = {
    name    = "grafana-container-${var.infrastructure_id}"
    image   = var.grafana_server_docker_image
    volumeMounts = [
      {
        name: "provisioning"
        mountPath: "/etc/grafana/provisioning"
      }, {
        name: "dashboards"
        mountPath: "/etc/grafana/dashboards"
      }, {
        name: "data"
        mountPath: "/var/lib/grafana"
      }
    ]

    env = [
      {
        name  = "GF_SECURITY_ADMIN_USER"
        value = var.monitoring_admin_username
      }, {
        name  = "GF_SECURITY_ADMIN_PASSWORD"
        value = random_string.monitoring-admin-password.result
      }, {
        name = "GF_ANALYTICS_REPORTING_ENABLED"
        value = "false"
      }, {
        name = "GF_ANALYTICS_CHECK_FOR_UPDATES"
        value = "false"
      }
    ]
    tty : true
    stdin : true
  }

  restart_policy = "Always"

  volumes = [
    {
      name = "provisioning"
      hostPath = {path="/etc/grafana/provisioning"}
    }, {
      name = "dashboards"
      hostPath = {path="/etc/grafana/dashboards"}
    }, {
      name = "data"
      gcePersistentDisk = {
        pdName="grafana-${var.infrastructure_id}-data-disk"
        fsType="ext4"
        }
    }
  ]
}

resource "google_compute_instance" "grafana" {
  name         = "grafana-server-${var.infrastructure_id}"
  machine_type = var.grafana_server_machine_type
  zone         = var.gcp_zone
  depends_on   = [google_project_service.services]


  # Allow to stop/start the machine to enable change machine type.
  allow_stopping_for_update = true

  # Use container os image as operating system.
  boot_disk {
    initialize_params {
      image = var.container_base_image
      size  = var.grafana_server_disk_size_gb
    }
  }

  attached_disk {
    source = google_compute_disk.grafd.self_link
    device_name = "grafana-${var.infrastructure_id}-data-disk"
    mode = "READ_WRITE"
  }

  network_interface {
    network       = var.vpc_network
  }

  # Tag for service enumeration.
  labels = {
    "turbinia-prometheus" = "true"
  }

  # Enable the GCE discovery module to call required APIs.
  service_account {
    scopes = ["compute-ro"]
  }

  metadata = {
    gce-container-declaration = module.grafana-container.metadata_value
    google-logging-enabled = "true"
    google-monitoring-enabled = "true"
  }

  # Provision the machine with a script.
  metadata_startup_script = data.template_file.grafana-startup-script.rendered
}
