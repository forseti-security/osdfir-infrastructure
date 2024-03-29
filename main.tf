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

terraform {
  # Use local state storage by default. For production environments please
  # consider  using a more robust backend.
  backend "local" {
    path = "terraform.tfstate"
  }

  # Use Google Cloud Storage for robust, collaborative state storage.
  # Note: The bucket name need to be globally unique.
  #backend "gcs" {
  #  bucket = "GLOBALLY UNIQ BUCKET NAME"
  #}
}

provider "google" {
  project  = var.gcp_project
  region   = var.gcp_region
}

#------------#
# Timesketch #
#------------#
module "timesketch" {
  source                       = "./modules/timesketch"
  gcp_project                  = var.gcp_project
  gcp_region                   = var.gcp_region
  gcp_zone                     = var.gcp_zone
  gcp_ubuntu_1804_image        = var.gcp_ubuntu_1804_image
  infrastructure_id            = coalesce(var.infrastructure_id, random_id.infrastructure-random-id.hex)
  vpc_network                  = var.vpc_network
}

#------------#
# Turbinia   #
#------------#
module "turbinia" {
  source                       = "./modules/turbinia"
  gcp_project                  = var.gcp_project
  gcp_region                   = var.gcp_region
  gcp_zone                     = var.gcp_zone
  infrastructure_id            = coalesce(var.infrastructure_id, random_id.infrastructure-random-id.hex)
  turbinia_created_by          = var.turbinia_created_by
  turbinia_creation_date       = var.turbinia_creation_date
  turbinia_docker_image_server = var.turbinia_docker_image_server
  turbinia_docker_image_worker = var.turbinia_docker_image_worker
  vpc_network                  = var.vpc_network
  debug_logs                   = var.debug_logs
}

#------------#
# Monitoring #
#------------#
module "monitoring" {
  source                       = "./modules/monitoring"
  gcp_project                  = var.gcp_project
  gcp_region                   = var.gcp_region
  gcp_zone                     = var.gcp_zone
  infrastructure_id            = coalesce(var.infrastructure_id, random_id.infrastructure-random-id.hex)
  vpc_network                  = var.vpc_network
}

# Random ID for creating unique resource names.
resource "random_id" "infrastructure-random-id" {
  byte_length = 8
}
