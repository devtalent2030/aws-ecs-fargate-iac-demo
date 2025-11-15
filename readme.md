# AWS ECS Fargate IaC Demo – Node.js ToDo App

> Production-style container deployment on AWS using CloudFormation, ECS Fargate, ALB, and ECR.

## Overview

This project demonstrates a complete, **infrastructure-as-code (IaC)** deployment of a containerized Node.js ToDo application on AWS.

The application is packaged into a Docker image, stored in **Amazon ECR**, and run on **AWS ECS Fargate** behind an **Application Load Balancer (ALB)** inside a dedicated **VPC**. Every piece of infrastructure – networking, security, compute, and logging – is created and managed via a single **CloudFormation template**.

Although this originated as a lab assignment, it is written and structured as a **real-world, reproducible cloud-native deployment** that can be extended into a larger system.

---

## Architecture

High-level architecture of the deployment:

* **Client (Browser)** → HTTP → **Application Load Balancer (ALB)**
* **ALB** → forwards traffic on port **80 → 3000** to
* **ECS Fargate Service** running

  * **Fargate Task** with a single containerized **Node.js ToDo app**
* All resources live inside a dedicated **VPC** with

  * Two **public subnets** (multi-AZ)
  * **Internet Gateway** and a public route table
* **Amazon ECR** stores the Docker image
* **Amazon CloudWatch Logs** stores container logs using the awslogs driver

Conceptual flow:

1. User opens the ALB DNS URL in their browser.
2. ALB receives the request on port 80 and forwards it to the ECS target group on port 3000.
3. ECS Fargate tasks run the Node.js ToDo application and return the HTTP response.
4. Application logs are streamed to **CloudWatch Logs** for observability and troubleshooting.

---

## Features

* **Full IaC deployment**

  * Single `cloudformation.yaml` file provisions all infrastructure
  * Reproducible: the entire stack can be created or destroyed in minutes

* **Containerized application**

  * Node.js ToDo app packaged into a Docker image
  * Built locally and pushed to **Amazon ECR**

* **Managed compute with ECS Fargate**

  * Serverless containers (no EC2 management)
  * Configured with `awsvpc` networking and public IP assignment

* **Layered networking design**

  * Custom **VPC** with `/16` CIDR
  * Two **public subnets** in different Availability Zones
  * Internet Gateway + route table with `0.0.0.0/0` default route

* **Secure and explicit access control**

  * ALB security group: allows inbound HTTP from the internet
  * ECS security group: only allows traffic from the ALB security group on port 3000

* **Logging and diagnostics**

  * Dedicated **CloudWatch Logs** log group for ECS tasks
  * ECS service events used for diagnosing deployment issues (e.g., image pulls, logging config)

---

## Tech Stack

**Cloud & Orchestration**

* AWS CloudFormation
* Amazon ECS (Fargate launch type)
* Application Load Balancer (ALB)
* Amazon ECR
* Amazon VPC, Subnets, Internet Gateway, Route Tables
* Amazon CloudWatch Logs

**Application**

* Node.js runtime (Node 18/20 Alpine base image)
* Express-based ToDo app with basic CRUD endpoints

**Tooling**

* Docker (with multi-architecture support on Apple Silicon)
* AWS CLI

---

## Repository Structure

Example structure used for the lab implementation:

```bash
aws-ecs-fargate-iac-demo/
├── Dockerfile
├── build-and-push.sh
├── cloudformation.yaml
├── compose.yaml              # Optional local testing
├── package.json
├── package-lock.json
├── src/
│   ├── index.js
│   ├── persistence/
│   │   ├── index.js
│   │   ├── postgres.js
│   │   └── sqlite.js
│   ├── routes/
│   │   ├── addItem.js
│   │   ├── deleteItem.js
│   │   ├── getItems.js
│   │   └── updateItem.js
│   └── static/
│       ├── css/
│       ├── js/
│       └── index.html
└── screenshots/
    ├── network.png
    ├── ecs-service.png
    └── website.png
```

---

## Infrastructure Details

### Networking

The `cloudformation.yaml` template provisions:

* **VPC**

  * CIDR: `10.0.0.0/16`
  * DNS support and hostnames: enabled
* **Subnets**

  * `10.0.1.0/24` – PublicSubnet1 (AZ 1)
  * `10.0.2.0/24` – PublicSubnet2 (AZ 2)
* **Internet Gateway** + **VPC Gateway Attachment**
* **Route Table**

  * `10.0.0.0/16` → `local`
  * `0.0.0.0/0` → Internet Gateway
* **Subnet Route Table Associations**

  * Both public subnets associated with the public route table

This yields a minimal but production-realistic public network layout suitable for a public-facing web application.

### Security Groups

* **ALB Security Group**

  * Inbound: `0.0.0.0/0` on TCP port **80**
  * Purpose: allow HTTP traffic from the internet to the ALB

* **ECS Security Group**

  * Inbound: TCP port **3000** from the **ALB security group only**
  * Purpose: restrict application container access to traffic that has already passed through the ALB

### Application Load Balancer

* Type: **application** (Layer 7)
* Subnets: both public subnets
* Listener: HTTP on port 80
* Target Group:

  * Target type: **ip** (for Fargate tasks)
  * Port: **3000**
  * Health check path: `/`

### ECS Cluster, Task Definition & Service

* **Cluster**

  * ECS cluster dedicated to this application (Fargate only)

* **Task Definition**

  * `Family`: e.g. `lab4-todo-task`
  * `NetworkMode`: `awsvpc`
  * `RequiresCompatibilities`: `FARGATE`
  * `CPU`: `256`, `Memory`: `512`
  * Container definition:

    * Name: `todo-app`
    * Image: `${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/lab4-todo-app:${ImageTag}`
    * Port mapping: container port 3000
    * Log driver: `awslogs` (CloudWatch Logs)

* **ECS Service**

  * Launch type: FARGATE
  * Desired count: 1
  * Network configuration: public subnets + ECS security group + public IP assignment
  * Attached to ALB target group on port 3000

### ECR & Logging

* **Amazon ECR**

  * Repository: `lab4-todo-app` (or prefixed variant for multi-user labs)
  * Image scanning on push: enabled

* **CloudWatch Logs**

  * Log group: `/ecs/lab4-todo` (or prefixed variant)
  * ECS tasks configured with `awslogs-group` and `awslogs-stream-prefix`

---

## Building & Pushing the Image

This project was developed on an Apple Silicon Mac (ARM64). ECS Fargate in the target region uses **linux/amd64**, so the build script explicitly sets the default platform.

Example `build-and-push.sh` flow:

```bash
#!/bin/bash
set -e

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
REPO_NAME=lab4-todo-app

# Login to ECR
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Build for linux/amd64 (Fargate runtime)
export DOCKER_DEFAULT_PLATFORM=linux/amd64

docker build -t "$REPO_NAME:latest" .

docker tag "$REPO_NAME:latest" \
  "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"

docker push "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"
```

This eliminates the common `image Manifest does not contain descriptor matching platform 'linux/amd64'` error when building on ARM laptops.

---

## Deploying with CloudFormation

With the Docker image pushed to ECR, the entire stack is deployed via a single CLI command.

```bash
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name Lab4FargateStack \
  --parameter-overrides ImageTag=latest \
  --capabilities CAPABILITY_IAM
```

Once the stack completes:

```bash
aws cloudformation describe-stacks \
  --stack-name Lab4FargateStack \
  --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' \
  --output text
```

Open the returned URL in a browser to access the ToDo application via the ALB.

---

## Verification & Screenshots

For academic submission and documentation, the following views are captured:

1. **Network configuration**

   * VPC details, subnets, route table, Internet Gateway, and subnet associations for the public route table.

2. **ECS Service status**

   * ECS cluster view showing the service with `desiredCount = 1` and `runningCount = 1`.

3. **Application in browser**

   * ToDo application loaded from the ALB URL with at least one item added.

These are stored under `screenshots/` and referenced in the report/README.

---

## Troubleshooting Notes

This project intentionally leans into **real-world debugging scenarios**, including:

* **CannotPullContainerError – image not found**

  * Caused by a mismatch between the image name/tag in ECR and the TaskDefinition.
  * Resolved by ensuring the ECR repository name and `Image` URI in the task definition are aligned, and by re-running the build-and-push script.

* **Platform mismatch – linux/amd64 vs arm64**

  * Seen when building images on Apple Silicon without specifying `DOCKER_DEFAULT_PLATFORM`.
  * Resolved by explicitly building for `linux/amd64`.

* **CloudWatch Logs: log group does not exist**

  * Occurred when ECS attempted to create log streams in a group that was not provisioned.
  * Resolved by creating the log group in CloudFormation and making the task definition depend on it.

* **ECR repository AlreadyExists errors in CloudFormation**

  * Triggered when re-running the stack while an ECR repository with the same name already exists.
  * Resolved by either deleting the repository first or externalizing ECR from the stack depending on the scenario.

These patterns mirror the sort of production issues that appear when teams adopt ECS/Fargate with IaC for the first time.

---

## Design Considerations & Extensions

Although the current implementation is intentionally minimal, it is designed with clear extension paths:

* **Parameterization**

  * Add parameters for VPC CIDR, subnet CIDRs, desired count, and application port.

* **Environment-specific stacks**

  * Introduce `Env` (dev/stage/prod) parameters and tag resources accordingly.

* **Private subnets + NAT**

  * Move Fargate tasks into private subnets and route outbound traffic via NAT Gateway, keeping only the ALB in public subnets.

* **HTTPS termination**

  * Attach an ACM certificate to the ALB and enable HTTPS listeners.

* **Autoscaling**

  * Add ECS Service Auto Scaling policies based on CPU, memory, or custom CloudWatch metrics.

* **Persistent data layer**

  * Wire the app to RDS or DynamoDB instead of in-memory / SQLite for stateful use cases.

---

## Why This Project Matters

From a recruiter’s or hiring manager’s perspective, this project shows:

* Ability to design and implement a **full cloud-native deployment path**: from containerizing an app to exposing it on the internet through managed AWS services.
* Practical experience with **ECS Fargate**, **ALB**, **ECR**, and **VPC networking** beyond “hello world” console clicks.
* Comfort with **infrastructure as code**, making environments reproducible, reviewable, and version-controlled.
* The capacity to debug real integration issues (image manifests, log groups, ECR repository conflicts) instead of stopping at the first error.

It demonstrates not just knowledge of individual AWS services, but an understanding of how they compose into a production-style deployment.

---

## License

This project was originally developed for educational purposes. You are free to adapt the structure and ideas for your own learning, labs, or internal demos.
