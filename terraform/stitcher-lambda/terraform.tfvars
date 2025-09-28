###############################################################################
# terraform.tfvars — Nimbus Transcribe overrides
###############################################################################

region          = "eu-west-1"
account_id      = "155186308102"
manifest_bucket = "nimbus-transcribe-ingest-155186308102-eu-west-1"
results_bucket  = "nimbus-transcribe-results-155186308102-eu-west-1"

# The Step Functions state machine that will call this Lambda
state_machine_arn = "arn:aws:states:eu-west-1:155186308102:stateMachine:openai-whisper-transcribe-map"

# (leave as "" to disable DDB/SNS integration till later)
job_table_name = ""
sns_topic_arn  = ""

