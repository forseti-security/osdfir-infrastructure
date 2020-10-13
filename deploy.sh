#!/bin/bash

set -e

if [ -z "$DEVSHELL_PROJECT_ID" ]; then
  echo "ERROR: Project ID unknown - please restart cloudshell"
  exit 1
fi

TIMESKETCH="1"
if [[ "$*" == *--no-timesketch* ]] ; then
  TIMESKETCH="0"
  echo "--no-timesketch found: Not deploying Timesketch."
fi

# TODO: Better flag handling
DOCKER_IMAGE=""
if [[ "$*" == *--build-release-test* ]] ; then
  DOCKER_IMAGE="-var turbinia_docker_image_server=gcr.io/oss-forensics-registry/turbinia/turbinia-server-release-test:latest"
  DOCKER_IMAGE="$DOCKER_IMAGE -var turbinia_docker_image_worker=gcr.io/oss-forensics-registry/turbinia/turbinia-worker-release-test:latest"
  echo "Setting docker image to $DOCKER_IMAGE"
elif [[ "$*" == *--build-dev* ]] ; then
  DOCKER_IMAGE="-var turbinia_docker_image_server=gcr.io/oss-forensics-registry/turbinia/turbinia-server-dev:latest"
  DOCKER_IMAGE="$DOCKER_IMAGE -var turbinia_docker_image_worker=gcr.io/oss-forensics-registry/turbinia/turbinia-worker-dev:latest"
  echo "Setting docker image to $DOCKER_IMAGE"
fi

# Use local `gcloud auth` credentials rather than creating new Service Account. 
if [[ "$*" != *--use-gcloud-auth* ]] ; then
  SA_NAME="terraform"
  SA_MEMBER="serviceAccount:$SA_NAME@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"

  # Create AppEngine app, if not already exists, in order to activate datastore
  if ! gcloud services list | grep appengine; then
    gcloud app create --region=us-central
  fi

  # Create service account
  gcloud iam service-accounts create "${SA_NAME}" --display-name "${SA_NAME}"

  # Grant IAM roles to the service account
  echo "Grant permissions on service account"
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/editor'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/compute.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/cloudfunctions.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/servicemanagement.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/pubsub.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/storage.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/redis.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/cloudsql.admin'

  # Create and fetch the service account key
  echo "Fetch and store service account key"
  gcloud iam service-accounts keys create ~/key.json --iam-account "$SA_NAME@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"
  export GOOGLE_APPLICATION_CREDENTIALS=~/key.json

# TODO: Do real check to make sure credentials have adequate roles
elif [[ $( gcloud auth list --filter="status:ACTIVE" --format="value(account)" | wc -l ) -eq 0 ]] ; then
  echo "No gcloud credentials found.  Use 'gcloud auth login' and 'gcloud auth application-default' to log in"
  exit 1
fi


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

# Deploy cloud functions
gcloud -q services enable cloudfunctions.googleapis.com
gcloud -q services enable cloudbuild.googleapis.com

# Deploying cloud functions is flaky. Retry until success.
while true; do
  num_functions="$(gcloud functions list | grep task | wc -l)"
  if [[ "${num_functions}" -eq "3" ]]; then
    echo "All Cloud Functions deployed"
    break
  fi
  gcloud -q functions deploy gettasks --source modules/turbinia/data/ --runtime nodejs10 --trigger-http --memory 256MB --timeout 60s
  gcloud -q functions deploy closetask --source modules/turbinia/data/ --runtime nodejs10 --trigger-http --memory 256MB --timeout 60s
  gcloud -q functions deploy closetasks --source modules/turbinia/data/ --runtime nodejs10 --trigger-http --memory 256MB --timeout 60s
done


# Run Terraform to setup the rest of the infrastructure
terraform init
if [ $TIMESKETCH -eq "1" ] ; then
  terraform apply -var gcp_project=$DEVSHELL_PROJECT_ID $DOCKER_IMAGE -auto-approve
else
  terraform apply --target=module.turbinia -var gcp_project=$DEVSHELL_PROJECT_ID $DOCKER_IMAGE -auto-approve
fi


if [ $TIMESKETCH -eq "1" ] ; then
  url="$(terraform output timesketch-server-url)"
  user="$(terraform output timesketch-admin-username)"
  pass="$(terraform output timesketch-admin-password)"

  echo
  echo "Waiting for Timesketch installation to finish. This may take a few minutes.."
  echo
  while true; do
    response="$(curl -k -o /dev/null --silent --head --write-out '%{http_code}' $url)"
    if [[ "${response}" -eq "302" ]]; then
      break
    fi
    sleep 3
  done

  echo "****************************************************************************"
  echo "Timesketch server: ${url}"
  echo "User: ${user}"
  echo "Password: ${pass}"
  echo "****************************************************************************"
fi


# Turbinia
cd ~
# TODO: Either add checks here, or possibly add a suffix with the infrastructure
# ID here.
virtualenv --python=/usr/bin/python2.7 turbinia
echo "Activating Turbinia virtual environment"
source turbinia/bin/activate

echo "Installing Turbinia client"
pip install turbinia 1>/dev/null
cd $DIR
terraform output turbinia-config > ~/.turbiniarc
sed -i s/"\/var\/log\/turbinia\/turbinia.log"/"\/tmp\/turbinia.log"/ ~/.turbiniarc

echo
echo "Deployment done"
echo
