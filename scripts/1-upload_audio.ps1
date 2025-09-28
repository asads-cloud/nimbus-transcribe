# 2) Pick a job id and upload under audio/<job-id>/...
$JOBID   = "task-0018"
$SRCKEY  = "audio/$JOBID/CD2.mp3"
aws s3 cp "audios/CD2.mp3" "s3://$INGEST/$SRCKEY" --content-type audio/mp3