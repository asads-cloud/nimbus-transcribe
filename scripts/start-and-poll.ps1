$SM_ARN = "arn:aws:states:eu-west-1:155186308102:stateMachine:openai-whisper-transcribe-map"

$exec = aws stepfunctions start-execution --state-machine-arn $SM_ARN --input file://artifacts/phase5_inputs.json | ConvertFrom-Json
$EXEC_ARN = $exec.executionArn
"Started: $EXEC_ARN"

do {
  Start-Sleep -Seconds 15
  $status = aws stepfunctions describe-execution --execution-arn $EXEC_ARN --query status --output text
  "Status: $status"
} while ($status -eq "RUNNING")
