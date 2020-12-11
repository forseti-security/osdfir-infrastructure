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
    "compute.googleapis.com",
    "datastore.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "storage-component.googleapis.com",
    "logging.googleapis.com"
  ]
}

resource "google_project_service" "services" {
  count              = length(local.services_list)
  project            = var.gcp_project
  service            = local.services_list[count.index]
  disable_on_destroy = false
}

# Enable PubSub and create topic
resource "google_pubsub_topic" "pubsub-topic" {
  name = "turbinia-${var.infrastructure_id}"
  depends_on  = [google_project_service.services]
}

resource "google_pubsub_topic" "pubsub-topic-psq" {
  name        = "turbinia-${var.infrastructure_id}-psq"
  depends_on  = [google_project_service.services]
}

# Cloud Storage Bucket
resource "google_storage_bucket" "output-bucket" {
  name          = "turbinia-${var.infrastructure_id}"
  depends_on    = [google_project_service.services]
  uniform_bucket_level_access = true
  force_destroy = true
}

# Bucket notfication for GCS importer
resource "google_pubsub_topic" "pubsub-topic-gcs" {
  name = "turbinia-gcs-${var.infrastructure_id}"
  depends_on  = [google_project_service.services]
}

data "google_storage_project_service_account" "gcs-pubsub-account" {
}

resource "google_pubsub_topic_iam_binding" "binding" {
  topic   = google_pubsub_topic.pubsub-topic-gcs.id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.gcs-pubsub-account.email_address}"]
}

resource "google_storage_notification" "notification" {
  bucket         = google_storage_bucket.output-bucket.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.pubsub-topic-gcs.id
  event_types    = ["OBJECT_FINALIZE", "OBJECT_METADATA_UPDATE"]
  custom_attributes = {
    new-attribute = "new-attribute-value"
  }
  depends_on = [google_pubsub_topic_iam_binding.binding]
}

resource "google_pubsub_subscription" "gcs-subscription" {
  name  = "turbinia-gcs-subscription-${var.infrastructure_id}"
  topic = google_pubsub_topic.pubsub-topic-gcs.name
  message_retention_duration = "1200s"
  retain_acked_messages      = true
  ack_deadline_seconds = 20
  expiration_policy {
    ttl = "300000.5s"
  }
}

# Template for systemd service file
data "template_file" "turbinia-systemd" {
  template = file("${path.module}/templates/turbinia.service.tpl")
}

# Turbinia config
data "template_file" "turbinia-config-template" {
  template = file("${path.module}/templates/turbinia.conf.tpl")
  vars = {
    project           = var.gcp_project
    region            = var.gcp_region
    zone              = var.gcp_zone
    turbinia_id       = var.infrastructure_id
    output_dir        = var.turbinia_output_directory
    tmp_dir           = var.turbinia_tmp_directory
    pubsub_topic      = google_pubsub_topic.pubsub-topic.name
    pubsub_topic_psq  = google_pubsub_topic.pubsub-topic-psq.name
    bucket            = google_storage_bucket.output-bucket.name
  }
  depends_on  = [google_project_service.services]
}

locals {
  turbinia_config = base64encode(data.template_file.turbinia-config-template.rendered)
}

# # Turbinia server
module "gce-server-container" {
  source = "terraform-google-modules/container-vm/google"

  container = {
    name    = "turbinia-server"
    image   = var.turbinia_docker_image_server

    securityContext = {
      privileged : false
    }
    env = [
      {
        name  = "TURBINIA_CONF"
        value = local.turbinia_config
      }
    ]
    tty : true
    stdin : true
  }

  restart_policy = "Always"
}

resource "google_compute_instance" "turbinia-server" {
  count        = var.turbinia_server_count
  name         = "turbinia-server-${var.infrastructure_id}"
  machine_type = var.turbinia_server_machine_type
  zone         = var.gcp_zone
  depends_on   = [google_project_service.services, google_pubsub_topic.pubsub-topic, google_pubsub_topic.pubsub-topic-psq]

  # Allow to stop/start the machine to enable change machine type.
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.container_base_image
      type = "pd-standard"
    }
  }

  metadata = {
    gce-container-declaration = module.gce-server-container.metadata_value
    google-logging-enabled = "true"
    google-monitoring-enabled = "true"
  }

  labels = {
    container-vm = module.gce-server-container.vm_container_label
    turbinia-prometheus = "true"
  }

  service_account {
    scopes = ["compute-ro", "storage-rw", "pubsub", "datastore", "logging-write"]
  }

  network_interface {
    network = "default"
  }
}


# # Turbinia worker
resource "google_compute_disk" "pd" {
  count   = var.turbinia_worker_count
  project = var.gcp_project
  name    = "turbinia-worker-${var.infrastructure_id}-${count.index}-data-disk"
  type    = "pd-standard"
  zone    = var.gcp_zone
  size    = 1000
}

module "gce-worker-container" {
  source = "terraform-google-modules/container-vm/google"
  count  = var.turbinia_worker_count

  container = {
    name    = "turbinia-worker-container-${count.index}"
    image   = var.turbinia_docker_image_worker
    volumeMounts = [
      {
        name: "host-path-0"
        mountPath: "/dev"
        readOnly: true
      }, {
        name: "data-disk-0"
        mountPath: "/var/lib/turbinia"
        readOnly: false
      }
    ]

    securityContext = {
      privileged : true
    }
    env = [
      {
        name  = "TURBINIA_CONF"
        value = local.turbinia_config
      }, {
        name  = "TURBINIA_OUTPUT_DIR"
        value = var.turbinia_output_directory
      }, {
        name  = "TURBINIA_TMP_DIR"
        value = var.turbinia_tmp_directory
      }
    ]
    tty : true
    stdin : true
  }

  restart_policy = "Always"
  volumes = [
    {
      name = "host-path-0"
      hostPath = {path="/dev"}
    }, {
      name = "data-disk-0"
      gcePersistentDisk = {
	pdName = "turbinia-worker-${var.infrastructure_id}-${count.index}-data-disk"
	fstype = "ext4"
      }
    },
  ]
}

resource "google_compute_instance" "turbinia-worker" {
  count        = var.turbinia_worker_count
  name         = "turbinia-worker-${var.infrastructure_id}-${count.index}"
  machine_type = var.turbinia_worker_machine_type
  zone         = var.gcp_zone
  depends_on   = [google_project_service.services, google_compute_instance.turbinia-server, google_compute_disk.pd]

  # Allow to stop/start the machine to enable change machine type.
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.container_base_image
      type = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.pd[count.index].self_link
    device_name = "turbinia-worker-${var.infrastructure_id}-${count.index}-data-disk"
    mode        = "READ_WRITE"
  }

  metadata = {
    gce-container-declaration = module.gce-worker-container[count.index].metadata_value
    google-logging-enabled = "true"
    google-monitoring-enabled = "true"
  }

  labels = {
    container-vm = module.gce-worker-container[count.index].vm_container_label
    turbinia-prometheus = "true"
  }

  service_account {
    scopes = ["compute-rw", "storage-rw", "pubsub", "datastore", "cloud-platform", "logging-write"]
  }

  network_interface {
    network = "default"
  }
}
