# vars you can tweak
$acct   = "155186308102"
$region = "eu-west-1"
$INGEST = "nimbus-transcribe-ingest-$acct-$region"
$RESULT = "nimbus-transcribe-results-$acct-$region"
$JOBID  = "task-0018"
$MANKEY = "manifests/$JOBID.jsonl"
$SM_ARN = "arn:aws:states:eu-west-1:155186308102:stateMachine:openai-whisper-transcribe-map"


$exec = aws stepfunctions start-execution --state-machine-arn $SM_ARN --input file://artifacts/task-input.json | ConvertFrom-Json
$EXEC_ARN = $exec.executionArn
do {
  Start-Sleep -Seconds 15
  $status = aws stepfunctions describe-execution --execution-arn $EXEC_ARN --query status --output text
  "Status: $status"
} while ($status -eq "RUNNING")