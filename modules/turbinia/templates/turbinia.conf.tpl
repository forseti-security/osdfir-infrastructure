# General
INSTANCE_ID         = 'turbinia-${turbinia_id}'
STATE_MANAGER       = 'Datastore'
TASK_MANAGER        = 'PSQ'
CLOUD_PROVIDER      = 'GCP'
OUTPUT_DIR          = '${output_dir}'
TMP_DIR             = '${tmp_dir}'
LOG_DIR             = '/var/log/turbinia'
LOG_FILE            = '/var/log/turbinia/turbinia.log'
LOCK_FILE           = '/var/lock/turbinia-worker.lock'
TMP_RESOURCE_DIR    = '/var/run/lock'
RESOURCE_FILE       = '${output_dir}/turbinia-state.json'
RESOURCE_FILE_LOCK  = '${output_dir}/turbinia-state.json.lock'
SCALEDOWN_WORKER_FILE = '${tmp_dir}/turbinia-to-scaledown.lock'
SLEEP_TIME          = 10
SINGLE_RUN          = False
MOUNT_DIR_PREFIX    = '/mnt/turbinia'
SHARED_FILESYSTEM   = False
DEBUG_TASKS         = False
RECIPE_FILE_DIR     = '/etc/turbinia/recipes'

# This will enable the usage of docker containers for the worker.
DOCKER_ENABLED = False

# Any jobs added to this list will disable it from being used.
DISABLED_JOBS = ['VolatilityJob', 'BinaryExtractorJob', 'BulkExtractorJob', 'DfdeweyJob', 'HindsightJob', 'PhotorecJob']

# Configure additional job dependency checks below.
DEPENDENCIES = [{
    'job': 'BinaryExtractorJob',
    'programs': ['image_export.py'],
    'docker_image': None,
    'timeout': 7200
}, {
    'job': 'BulkExtractorJob',
    'programs': ['bulk_extractor'],
    'docker_image': None,
    'timeout': 14400
}, {
    'job': 'DfdeweyJob',
    'programs': ['dfdewey'],
    'docker_image': None,
    'timeout': 86400
}, {
    'job': 'DockerContainersEnumerationJob',
    'programs': ['de.py'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'FsstatJob',
    'programs': ['fsstat'],
    'docker_image': None,
    'timeout': 1800
}, {
    'job': 'GrepJob',
    'programs': ['grep'],
    'docker_image': None,
    'timeout': 1800
}, {
    'job': 'HadoopAnalysisJob',
    'programs': ['strings'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'HindsightJob',
    'programs': ['hindsight.py'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'JenkinsAnalysisJob',
    'programs': ['hashcat'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'LinuxAccountAnalysisJob',
    'programs': ['hashcat'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'LokiAnalysisJob',
    'programs': ['/opt/loki/loki.py'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'PartitionEnumerationJob',
    'programs': ['bdemount'],
    'docker_image': None,
    'timeout': 1200
}, {
    'job': 'PlasoJob',
    'programs': ['log2timeline.py'],
    'docker_image': None,
    'timeout': 86400
}, {
    'job': 'PhotorecJob',
    'programs': ['photorec'],
    'docker_image': None,
    'timeout': 14400
}, {
    'job': 'PsortJob',
    'programs': ['psort.py'],
    'docker_image': None,
    'timeout': 3600
}, {
    'job': 'StringsJob',
    'programs': ['strings'],
    'docker_image': None,
    'timeout': 3600
}, {
    'job': 'VolatilityJob',
    'programs': ['vol.py'],
    'docker_image': None,
    'timeout': 3600
}, {
    'job': 'WindowsAccountAnalysisJob',
    'programs': ['hashcat', 'secretsdump.py'],
    'docker_image': None,
    'timeout': 3600
}, {
    'job': 'WordpressCredsAnalysisJob',
    'programs': ['hashcat', 'grep', 'strings'],
    'docker_image': None,
    'timeout': 3600
}]

# Prometheus monitoring config
PROMETHEUS_ENABLED = True
PROMETHEUS_ADDR = '0.0.0.0'
PROMETHEUS_PORT = 9200

# GCP
TURBINIA_PROJECT      = '${project}'
TURBINIA_REGION       = '${region}'
TURBINIA_ZONE         = '${zone}'
BUCKET_NAME           = '${bucket}'
PSQ_TOPIC             = '${pubsub_topic_psq}'
PUBSUB_TOPIC          = '${pubsub_topic}'
GCS_OUTPUT_PATH       = 'gs://${bucket}/output'
STACKDRIVER_LOGGING   = True
STACKDRIVER_TRACEBACK = True

# Celery
CELERY_BROKER         = None
CELERY_BACKEND        = None
KOMBU_BROKER          = None
KOMBU_CHANNEL         = None
KOMBU_DURABLE         = True
REDIS_HOST            = None
REDIS_PORT            = None
REDIS_DB              = None

# Email notification config
EMAIL_NOTIFICATIONS = False
EMAIL_HOST_ADDRESS = None
EMAIL_PORT = None
EMAIl_ADDRESS = None
EMAIl_PASSWORD = None 
