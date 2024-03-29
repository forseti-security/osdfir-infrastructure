#!/bin/bash
# Copyright 2019 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Exit on any error.
set -e

# Default constants.
readonly BOOT_FINISHED_FILE="/var/lib/cloud/instance/boot-finished"
readonly STARTUP_FINISHED_FILE="/var/lib/cloud/instance/startup-script-finished"

# Redirect stdout and stderr to logfile.
exec >> /var/log/terraform_provision.log
exec 2>&1

# Exit if the startup script has already been executed successfully.
if [[ -f "$${STARTUP_FINISHED_FILE}" ]]; then
  exit 0
fi

# Wait for cloud-init to finish all tasks.
until [[ -f "$${BOOT_FINISHED_FILE}" ]]; do
  sleep 1
done

# Format attached disk and set owner as nobody for mounting
sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard -E root_owner=65534:65534 /dev/disk/by-id/google-"${prom-disk}"

# Configure Prometheus.
mkdir /etc/prometheus
wget https://raw.githubusercontent.com/google/turbinia/master/monitoring/prometheus/prometheus.yaml -O /etc/prometheus/prometheus.yml

# Set GCP project/zone.
sed -i s/"<project>"/"${project}"/ /etc/prometheus/prometheus.yml
sed -i s/"<zone>"/"${zone}"/ /etc/prometheus/prometheus.yml

# --- END MAIN ---

date > "$${STARTUP_FINISHED_FILE}"
echo "Startup script finished successfully"