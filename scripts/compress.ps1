Compress-Archive -Force `
  -Path .\lambdas\stitcher\handler.py `
  -DestinationPath .\artifacts\lambda\stitcher.zip

cd terraform\stitcher-lambda
terraform init -upgrade
terraform apply -auto-approve
cd ../..


Compress-Archive -Force `
  -Path .\lambdas\prepare\handler.py `
  -DestinationPath .\artifacts\lambda\prepare.zip

cd terraform\prepare-lambda
terraform init -upgrade
terraform apply -auto-approve
cd ../..