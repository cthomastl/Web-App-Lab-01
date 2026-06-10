# Flask App Monitor — AWS Lab

A Python Flask monitoring application deployed on AWS EC2 using Terraform and Docker.

> **Note:** One component in this setup is intentionally misconfigured. You will encounter it when testing the deployed application. Use the Linux command line tools and Docker commands described below to find and fix it.

---

## Directory Structure

```
web-app-lab-01/
├── README.md
├── Dockerfile                  # Container definition for the Flask app
├── docker-compose.yml          # Orchestrates Flask + Nginx services
├── app.py                      # Flask application (routes: /, /health, /logs)
├── requirements.txt            # Python dependencies
├── templates/
│   └── index.html              # HTML frontend
├── nginx/
│   └── nginx.conf              # Nginx reverse proxy configuration
├── scripts/
│   ├── health_check.sh         # Checks disk, memory, and container status
│   ├── log_rotate.sh           # Archives and resets the Flask log file
│   └── deploy.sh               # Rebuilds and restarts the Flask container
└── terraform/
    ├── main.tf                 # EC2 instance and security group
    ├── variables.tf            # Input variables (region, AMI, key pair, etc.)
    ├── outputs.tf              # Outputs: public IP, app URLs, SSH command
    └── user_data.sh            # Boot script: installs Docker, writes files, starts app
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- An AWS account with credentials configured (`~/.aws/credentials` or environment variables)
- An existing EC2 key pair in `us-east-1`

---

## Deploy with Terraform

### 1. Initialize

```bash
cd terraform
terraform init
```

### 2. Plan

Replace `my-key-pair` with the name of your existing EC2 key pair.

```bash
terraform plan -var="key_pair_name=my-key-pair"
```

Review the plan output. You should see one security group and one EC2 instance being created.

### 3. Apply

```bash
terraform apply -var="key_pair_name=my-key-pair"
```

Type `yes` when prompted. Terraform will print the public IP and URLs when it finishes.

The EC2 instance runs its setup script on first boot. Wait 3–5 minutes after `apply` completes before testing the application.

### 4. Destroy (when done)

```bash
terraform destroy -var="key_pair_name=my-key-pair"
```

---

## SSH into the Instance

Use the public IP printed by Terraform:

```bash
ssh -i ~/.ssh/my-key-pair.pem ec2-user@<PUBLIC_IP>
```

### Verify everything is running

```bash
docker ps
```

```bash
docker logs flask_app
```

```bash
docker logs nginx_proxy
```

```bash
curl http://localhost:5000/health
```

```bash
curl http://localhost:80
```

```bash
cat /var/log/user_data.log
```

```bash
cat /var/log/flaskapp/app.log
```

```bash
cat /var/log/scripts/health.log
```

---

## Running the Scripts

```bash
sudo /opt/scripts/health_check.sh
```

```bash
sudo /opt/scripts/log_rotate.sh
```

```bash
sudo /opt/scripts/deploy.sh
```

---

## Practice Problems

These problems require you to work directly against the running application using Linux command line tools. No answers or hints are provided.

1. When you navigate to the public IP in a browser, you see an error instead of the frontend. Use Docker and standard Linux tools to identify the root cause and fix it without running `terraform apply` again.

2. The `/health` endpoint reports "uptime" based on how long the Flask process has been running, not how long the EC2 instance has been up. What command shows you actual system uptime? Write a one-liner that compares the two values side by side.

3. You suspect the health check cron job stopped running. What files would you inspect to confirm whether the cron daemon is active and whether the job is scheduled correctly? List the exact commands.

4. The `app.log` file has grown to several hundred megabytes. Without stopping the Flask container, rotate the log and verify that new requests are still being written to a fresh log file after the rotation.

5. Write a one-liner using `grep` and `awk` against `/var/log/flaskapp/app.log` that counts how many times each route (`/`, `/health`, `/logs`) has been called today.

6. A teammate reports that the Flask container has been restarting repeatedly. What command shows you container restart counts, and what command streams the container's live output so you can watch it crash in real time?

7. You need to know the exact process ID of the Python interpreter running inside the Flask container. Find it using only commands run on the EC2 host (not inside the container).

8. Write a new script at `/opt/scripts/disk_alert.sh` that prints `WARNING: disk usage at X%` if root filesystem usage exceeds 70%, and `OK` otherwise. Make it safe to call from cron.

9. Find all log entries in `/var/log/flaskapp/app.log` where `status_code` is not `200` and print them sorted by timestamp. Write this as a single pipeline command.

10. The `/var/log/flaskapp/archive/` directory is accumulating rotated log files. Write a command that lists all archive files sorted by size (largest first) and prints the total disk space used by the archive directory.
