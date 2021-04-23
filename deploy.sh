#!/bin/bash

set -e

TURBINIA_CONFIG="$HOME/.turbiniarc"
TURBINIA_REGION=us-central1
VPC_NETWORK="default"

if [[ "$*" == *--help ]] ; then
  echo "Terraform deployment script for Turbinia and Timesketch"
  echo "Options:"
  echo "--no-timesketch                Do not deploy timesketch"
  echo "--no-turbinia                  Do not deploy turbinia"
  echo "--build-release-test           Deploy Turbinia release test docker image"
  echo "--build-dev                    Deploy Turbinia development docker image"
  echo "--build-experimental           Deploy Turbinia experimental docker image"
  echo "--use-gcloud-auth              Use gcloud authentication instead of a service key"
  echo "--no-cloudnat                  Do not deploy a Cloud NAT router"
  echo "--no-cloudfunctions            Do not deploy Turbinia Cloud Functions"
  echo "--no-datastore                 Do not configure Turbinia Datastore"
  echo "--no-virtualenv                Do not install the Turbinia client in a virtual env"
  echo "--no-monitoring                Do not deploy the monitoring infrastructure"
  exit 1
fi

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

# Check if the configured VPC network exists.
networks=$(gcloud -q compute networks list --filter="name=$VPC_NETWORK" |wc -l)
if [[ "${networks}" -lt "2" ]]; then
        echo "ERROR: VPC network $VPC_NETWORK not found, please create this first."
        exit 1
fi

echo "Deploying to project $DEVSHELL_PROJECT_ID"


TIMESKETCH="1"
if [[ "$*" == *--no-timesketch* ]] ; then
  TIMESKETCH="0"
  echo "--no-timesketch found: Not deploying Timesketch."
fi

TURBINIA="1"
if [[ "$*" == *--no-turbinia* ]] ; then
  TURBINIA="0"
  echo "--no-turbinia found: Not deploying Turbinia."
else
  # TODO: Better flag handling
  DOCKER_IMAGE=""
  if [[ "$*" == *--build-release-test* ]] ; then
    DOCKER_IMAGE="-var turbinia_docker_image_server=us-docker.pkg.dev/osdfir-registry/turbinia/release/turbinia-server-release-test:latest"
    DOCKER_IMAGE="$DOCKER_IMAGE -var turbinia_docker_image_worker=us-docker.pkg.dev/osdfir-registry/turbinia/release/turbinia-worker-release-test:latest"
    echo "Setting docker image to $DOCKER_IMAGE"
  elif [[ "$*" == *--build-dev* ]] ; then
    DOCKER_IMAGE="-var turbinia_docker_image_server=us-docker.pkg.dev/osdfir-registry/turbinia/release/turbinia-server-dev:latest"
    DOCKER_IMAGE="$DOCKER_IMAGE -var turbinia_docker_image_worker=us-docker.pkg.dev/osdfir-registry/turbinia/release/turbinia-worker-dev:latest"
    echo "Setting docker image to $DOCKER_IMAGE"
  elif [[ "$*" == *--build-experimental* ]] ; then
    DOCKER_IMAGE="-var turbinia_docker_image_server=us-docker.pkg.dev/osdfir-registry/turbinia/release/turbinia-server-experimental:latest"
    DOCKER_IMAGE="$DOCKER_IMAGE -var turbinia_docker_image_worker=us-docker.pkg.dev/osdfir-registry/turbinia/release/turbinia-worker-experimental:latest"
    echo "Setting docker image to $DOCKER_IMAGE"
  fi
fi

# Use local `gcloud auth` credentials rather than creating new Service Account.
if [[ "$*" != *--use-gcloud-auth* ]] ; then
  SA_NAME="terraform"
  SA_MEMBER="serviceAccount:$SA_NAME@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"

  if ! gcloud --project $DEVSHELL_PROJECT_ID iam service-accounts list |grep terraform; then
    # Create service account
    gcloud --project $DEVSHELL_PROJECT_ID iam service-accounts create "${SA_NAME}" --display-name "${SA_NAME}"
  fi

  # Grant IAM roles to the service account
  echo "Grant permissions on service account"
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/cloudfunctions.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/cloudsql.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/compute.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/datastore.indexAdmin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/editor'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/logging.logWriter'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/pubsub.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/redis.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/servicemanagement.admin'
  gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=$SA_MEMBER --role='roles/storage.admin'

  # Create and fetch the service account key
  echo "Fetch and store service account key"
  gcloud --project $DEVSHELL_PROJECT_ID iam service-accounts keys create ~/key.json --iam-account "$SA_NAME@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com"
  export GOOGLE_APPLICATION_CREDENTIALS=~/key.json

# TODO: Do real check to make sure credentials have adequate roles
elif [[ $( gcloud auth list --filter="status:ACTIVE" --format="value(account)" | wc -l ) -eq 0 ]] ; then
  echo "No gcloud credentials found.  Use 'gcloud auth login' and 'gcloud auth application-default' to log in"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

# Enable "Private Google Access" on default VPC network so GCE instances without 
# an External IP can access Google log and monitoring service APIs.
gcloud compute --project $DEVSHELL_PROJECT_ID networks subnets update $VPC_NETWORK --region=$TURBINIA_REGION --enable-private-ip-google-access
# Allow IAP so that we can still connect to these via gcloud and cloud console.
# https://cloud.google.com/iap/docs/using-tcp-forwarding#tunneling_with_ssh
if ! gcloud compute --project $DEVSHELL_PROJECT_ID firewall-rules list | grep "allow-ssh-ingress-from-iap"; then
  gcloud compute --project $DEVSHELL_PROJECT_ID firewall-rules create allow-ssh-ingress-from-iap --direction=INGRESS --action=allow --rules=tcp:22 --source-ranges=35.235.240.0/20
fi

# Enable the Cloud NAT router so VMs have internet connectivity
if [[ "$*" != *--no-cloudnat* ]] ; then
  if ! gcloud compute routers list | grep nat-router; then
    echo "Setting up Cloud NAT router"
    gcloud --project $DEVSHELL_PROJECT_ID compute routers create nat-router --network=$VPC_NETWORK --region=$TURBINIA_REGION
    gcloud --project $DEVSHELL_PROJECT_ID compute routers nats create nat-config --router-region=$TURBINIA_REGION --router=nat-router --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips
  fi
fi

# Deploy cloud functions
if [[ "$*" != *--no-cloudfunctions* ]] ; then
  gcloud -q services --project $DEVSHELL_PROJECT_ID enable cloudfunctions.googleapis.com
  gcloud -q services --project $DEVSHELL_PROJECT_ID enable cloudbuild.googleapis.com

  # Deploying cloud functions is flaky. Retry until success.
  while true; do
    num_functions="$(gcloud functions --project $DEVSHELL_PROJECT_ID list | grep task | grep $TURBINIA_REGION | wc -l)"
    if [[ "${num_functions}" -eq "3" ]]; then
      echo "All Cloud Functions deployed"
      break
    fi
    gcloud --project $DEVSHELL_PROJECT_ID -q functions deploy gettasks --region $TURBINIA_REGION --source modules/turbinia/data/ --runtime nodejs10 --trigger-http --memory 256MB --timeout 60s
    gcloud --project $DEVSHELL_PROJECT_ID -q functions deploy closetask --region $TURBINIA_REGION --source modules/turbinia/data/ --runtime nodejs10 --trigger-http --memory 256MB --timeout 60s
    gcloud --project $DEVSHELL_PROJECT_ID -q functions deploy closetasks  --region $TURBINIA_REGION --source modules/turbinia/data/ --runtime nodejs10 --trigger-http --memory 256MB --timeout 60s
  done
fi

# Deploy Datastore indexes
if [[ "$*" != *--no-datastore* ]] ; then
  gcloud --project $DEVSHELL_PROJECT_ID -q services enable datastore.googleapis.com
  gcloud --project $DEVSHELL_PROJECT_ID -q datastore indexes create $DIR/modules/turbinia/data/index.yaml
fi

# Run Terraform to setup the rest of the infrastructure
terraform init
if [ $TIMESKETCH -eq "1" ] ; then
  terraform apply -var gcp_project=$DEVSHELL_PROJECT_ID $DOCKER_IMAGE -var vpc_network=$VPC_NETWORK -auto-approve
elif [ $TURBINIA -eq "1" ] ; then
  terraform apply --target=module.turbinia -var gcp_project=$DEVSHELL_PROJECT_ID $DOCKER_IMAGE -var vpc_network=$VPC_NETWORK  -auto-approve
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
if [[ "$*" == *--no-virtualenv* ]] ; then
  echo "Not creating virtualenv"
else
  echo "Creating virtualenv in ~/turbinia"
  cd ~
  # TODO: Either add checks here, or possibly add a suffix with the infrastructure
  # ID here.
  virtualenv --python=/usr/bin/python3 turbinia
  echo "Activating Turbinia virtual environment"
  source turbinia/bin/activate

  echo "Installing Turbinia client"
  pip install turbinia 1>/dev/null
  cd $DIR
fi

if [[ -a $TURBINIA_CONFIG ]] ; then
  backup_file="${TURBINIA_CONFIG}.$( date +%s )"
  mv $TURBINIA_CONFIG $backup_file
  echo "Backing up old Turbinia config $TURBINIA_CONFIG to $backup_file"
fi

# Monitoring infrastructure
if [[ "$*" == *--no-monitoring* ]] ; then
  echo "--no-monitoring found: Not deploying monitoring infrastructure."
else
  terraform apply --target=module.monitoring -var gcp_project=$DEVSHELL_PROJECT_ID -var vpc_network=$VPC_NETWORK  -auto-approve
  terraform refresh -var gcp_project=$DEVSHELL_PROJECT_ID 
  user="$(terraform output monitoring-admin-username)"
  pass="$(terraform output monitoring-admin-password)"
  
  echo "****************************************************************************"
  echo "Grafana Credentials"
  echo "User: ${user}"
  echo "Password: ${pass}"
  echo "****************************************************************************"
fi

if [[ $TURBINIA -eq "1" ]] ; then
  terraform output -raw turbinia-config > $TURBINIA_CONFIG
  sed -i s/"\/var\/log\/turbinia\/turbinia.log"/"\/tmp\/turbinia.log"/ $TURBINIA_CONFIG
fi

echo
echo "Deployment done"
echo