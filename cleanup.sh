#!/bin/bash
set -e

TURBINIA_CONFIG="$HOME/.turbiniarc"
TURBINIA_REGION=us-central1

if [[ -z "$( which terraform )" ]] ; then
  echo "Terraform CLI not found.  Please follow the instructions at "
  echo "https://learn.hashicorp.com/tutorials/terraform/install-cli to install"
  echo "the terraform CLI first."
  exit 1
fi

if [[ -z "$( which gcloud )" ]] ; then
  echo "gcloud CLI not found.  Please follow the instructions at "
  echo "https://cloud.google.com/sdk/docs/install to install the gcloud "
  echo "package first."
  exit 1
fi

if [[ -z "$DEVSHELL_PROJECT_ID" ]] ; then
  DEVSHELL_PROJECT_ID=$(gcloud config get-value project)
  ERRMSG="ERROR: Could not get configured project. Please either restart "
  ERRMSG+="Google Cloudshell, or set configured project with "
  ERRMSG+="'gcloud config set project PROJECT' when running outside of Cloudshell."
  if [[ -z "$DEVSHELL_PROJECT_ID" ]] ; then
    echo $ERRMSG
    exit 1
  fi
  echo "Environment variable \$DEVSHELL_PROJECT_ID was not set at start time "
  echo "so attempting to get project config from gcloud config."
  echo -n "Do you want to use $DEVSHELL_PROJECT_ID as the target project? (y / n) > "
  read response
  if [[ $response != "y" && $response != "Y" ]] ; then
    echo $ERRMSG
    exit 1
  fi
fi

echo -n " You are about to destroy resources in this project ($DEVSHELL_PROJECT_ID), are you sure? (y / n) > "
read response
if [[ $response != "y" && $response != "Y" ]] ; then
  exit 0
fi

echo "Destroying in project $DEVSHELL_PROJECT_ID"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "DIR: $DIR"
cd $DIR

echo "Remove VPC Private Google Access and firewall rule"
# Disable "Private Google Access" on default VPC network
gcloud compute --project $DEVSHELL_PROJECT_ID networks subnets update default --region=$TURBINIA_REGION --no-enable-private-ip-google-access
# Remove IAP firewall access rule
if ! gcloud compute --project $DEVSHELL_PROJECT_ID firewall-rules list | grep "allow-ssh-ingress-from-iap"; then
  gcloud compute --project $DEVSHELL_PROJECT_ID firewall-rules delete allow-ssh-ingress-from-iap
fi

# Remove cloud functions
if [[ "$*" != *--no-cloudfunctions* ]] ; then
  echo "Delete Google Cloud functions"
  if gcloud functions --project $DEVSHELL_PROJECT_ID list | grep gettasks; then
    gcloud --project $DEVSHELL_PROJECT_ID -q functions delete gettasks --region $TURBINIA_REGION
  fi
  if gcloud functions --project $DEVSHELL_PROJECT_ID list | grep closetask; then
    gcloud --project $DEVSHELL_PROJECT_ID -q functions delete closetask --region $TURBINIA_REGION
  fi
  if gcloud functions --project $DEVSHELL_PROJECT_ID list | grep closetasks; then
    gcloud --project $DEVSHELL_PROJECT_ID -q functions delete closetasks  --region $TURBINIA_REGION
  fi
fi

# Cleanup Datastore indexes
echo "Cleaning up Datastore indexes"
cp $DIR/modules/turbinia/data/index-empty.yaml index.yaml
gcloud --project $DEVSHELL_PROJECT_ID -q datastore indexes cleanup $DIR/modules/turbinia/data/index.yaml
rm index.yaml

# Run Terraform to destroy the rest of the infrastructure
echo "Running Terraform Destroy"
terraform destroy -auto-approve -var gcp_project=$DEVSHELL_PROJECT_ID

# Use local `gcloud auth` credentials so no need to cleanup Service Account.
if [[ "$*" != *--use-gcloud-auth* ]] ; then
  SA_NAME="terraform"
  SA_MEMBER="serviceAccount:$SA_NAME@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"

  # Delete IAM roles from the service account
  echo "Delete permissions on service account"
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/cloudfunctions.admin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/cloudsql.admin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/compute.admin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/datastore.indexAdmin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/editor'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/logging.logWriter'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/pubsub.admin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/redis.admin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/servicemanagement.admin'
  gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:$SA_MEMBER --role='roles/storage.admin'

  # Delete service account
  echo "Delete service account"
  gcloud --project $DEVSHELL_PROJECT_ID iam service-accounts delete "${SA_NAME}" 

  # Remove the service account key
  echo "Remove service account key"
  rm ~/key.json

# TODO: Do real check to make sure credentials have adequate roles
elif [[ $( gcloud auth list --filter="status:ACTIVE" --format="value(account)" | wc -l ) -eq 0 ]] ; then
  echo "No gcloud credentials found.  Use 'gcloud auth login' and 'gcloud auth application-default' to log in"
  exit 1
fi

# Remove Turbinia virtualenv and configuration
if [[ "$*" == *--no-virtualenv* ]] ; then
  echo "Not deleting Turbinia virtualenv"
else
  echo "Deleting virtualenv from ~/turbinia"
  cd ~
  rm -fr turbinia
fi
if [[ -a $TURBINIA_CONFIG ]] ; then
  echo "Removing Turbinia configuration file from $TURBINIA_CONFIG"
  rm $TURBINIA_CONFIG
fi

echo
echo "Cleanup done"
echo
