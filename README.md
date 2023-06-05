# Notice of Archiving

Dear Forseti users,

We are writing to inform you that we plan to archive the Forseti-Security repository.

Over the past few years, GCP Security has introduced a host of new features and capabilities that have addressed many security challenges targeted by Forseti. With low community engagement and limited improvements in the last two years, we have decided to place Forseti Security in archive. Note that other repos such as Forseti Real-Time-Enforcer and Resource-Policy-Evaliation-Library have also been automatically archived in February 2023 following no activities.

We plan to complete the archiving process by the end of June 2023.

What does this mean for you?

* The Forseti-Security repository will be read-only, meaning that users will not be able to modify or contribute additional code.
* You will however be able to fork or clone the repository and continue to use it however bearing ownership of your instance.
* There will be no additional support from Google on Forseti. We are moving the existing support teams to new projects.

We thank you for your active engagement over the last few years. 

---

**Note**: ***This installation method will be deprecated by the end of 2022. 
The recommended method for installing Timesketch is
[here](https://timesketch.org/guides/admin/install/) and the recommended
method for installing Turbinia is
[here](https://turbinia.readthedocs.io/en/latest/user/install-gke.html).***

**Note**: This setup will add billing costs to your project.

## Installing Terraform

Please follow [these
instructions](https://www.terraform.io/intro/getting-started/install.html) to
install Terraform binary on your machine.

## Setting up a Google Cloud Project

1.  Create a new project in GCP console
    ([link](https://console.cloud.google.com/project)). Let's assume it's called
    "gcp-forensics-deployment-test".
1.  Enable billing for the project
    ([link](https://support.google.com/cloud/answer/6293499#enable-billing)).

## Instrumenting Terraform with credentials

1.  In Cloud Platform Console, navigate to the [Create service account
    key](https://console.cloud.google.com/apis/credentials/serviceaccountkey)
    page.
1.  From the Service account dropdown, select Compute Engine default service
    account, and leave JSON selected as the key type.
1.  Click Create, which downloads your credentials as a file named
    `[PROJECT_ID]-[UNIQUE_ID].json`.
1.  In the same shell where you're going to run Terraform (see below), run the
    following:

```bash
export GCLOUD_KEYFILE_JSON=/absolute/path/to/downloaded-file.json
```

## Running Terraform

`cd` to the folder with Terraform configuration files (and where this README
file is).

If it's the first time you run Terraform with this set of configuration files,
run:

```bash
terraform init
```

Then run (`gcp-forensics-deployment-test` is the name of a project that you've previously
set up):

```bash
terraform apply -var 'gcp_project=gcp-forensics-deployment-test'
```

Run the following to get information about the newly deployed infrastructure:

```bash
terraform output
```
