#!/bin/bash
set -e

# Get account & region
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

# Login to ECR
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# IMPORTANT: build image for linux/amd64 (Fargate's platform)
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# Build image
docker build -t lab4-todo-app:latest .

# Tag image
docker tag lab4-todo-app:latest \
  $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/lab4-todo-app:latest

# Push
docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/lab4-todo-app:latest

echo "Image pushed for linux/amd64! Use ImageTag: latest in CloudFormation"