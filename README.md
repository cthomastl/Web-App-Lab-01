# Northside Ballers — AWS Container Lab

A basketball team roster app deployed on AWS EC2 using Terraform, Docker, and PostgreSQL.
The frontend loads team data from a Flask API. The API reads and writes to a Postgres database.

Three containers run behind Nginx:

```
Browser -> nginx_proxy (port 80) -> flask_app (port 5000) -> postgres_db (port 5432)
```

> **Something in this setup is broken.** The page will load, but one feature will not work.
> Use SSH, docker commands, and Linux tools to find and fix it.

---

## Directory Structure

```
web-app-lab-01/
├── README.md
├── Dockerfile                        # Flask app container
├── docker-compose.yml                # All three services + named volume
├── app.py                            # Flask API: GET/POST /api/players, DELETE /api/players/<id>
├── requirements.txt
├── initdb/
│   └── 01_init.sql                   # Runs on first Postgres startup: creates table, seeds roster
├── templates/
│   └── index.html                    # Team roster page with add/remove player form
├── nginx/
│   └── nginx.conf                    # Reverse proxy config
├── scripts/
│   ├── db_backup.sh                  # pg_dump the database to /var/backups/basketball/
│   ├── check_containers.sh           # Verify all containers are running; restart if not
│   └── seed_players.sh               # Wipe and re-seed the players table
└── terraform/
    ├── main.tf                       # EC2 instance + security group
    ├── variables.tf                  # key_pair_name (required), region, AMI, instance type
    ├── outputs.tf                    # Public IP, app URL, SSH command
    └── user_data.sh                  # Boot script: installs Docker, writes files, starts app
```

---

## Prerequisites

- Terraform >= 1.5
- AWS credentials configured (`~/.aws/credentials` or environment variables)
- An existing EC2 key pair in us-east-1

---

## Deploy

### 1. Initialize

```bash
cd terraform
terraform init
```

### 2. Plan

```bash
terraform plan -var="key_pair_name=your-key-name"
```

### 3. Apply

```bash
terraform apply -var="key_pair_name=your-key-name"
```

Wait 3-5 minutes after apply finishes. The EC2 instance runs the boot script to install
Docker, build the Flask image, and start all three containers.

### 4. Destroy when done

```bash
terraform destroy -var="key_pair_name=your-key-name"
```

---

## SSH and Verify

```bash
ssh -i ~/.ssh/your-key-name.pem ec2-user@<PUBLIC_IP>
```

Check container status:

```bash
docker ps
```

Check the boot log to confirm setup completed:

```bash
cat /var/log/user_data.log
```

Check Flask application logs:

```bash
cat /var/log/flaskapp/app.log
```

Test the Flask API directly (bypassing nginx):

```bash
curl http://localhost:5000/api/players
```

Test through nginx:

```bash
curl http://localhost:80/api/players
```

---

## Running the Scripts

```bash
sudo /opt/scripts/db_backup.sh
```

```bash
sudo /opt/scripts/check_containers.sh
```

```bash
sudo /opt/scripts/seed_players.sh
```

---

## Troubleshooting Challenges

These require you to SSH into the EC2 instance and work directly against the running system.
No answers or hints are provided.

**1.** The page loads but the roster does not populate — the table shows an error instead of player names.
Find the container that is causing the failure, read its logs, and identify the exact error message.
Fix the problem without rebuilding images or running `terraform apply` again.

**2.** After fixing the roster, exec into the Flask container and inspect all of its environment variables.
Which variable was set incorrectly, what was its value, and what should it be?
What is the difference between `localhost` and a service name inside a Docker network?

**3.** From inside the Flask container, use Python to test the database connection on both the wrong hostname
and the correct one before making any changes. What exception is raised and what does it tell you?

**4.** Inspect the Docker network that the containers share. Find the internal IP address of the Postgres container.
Then use `nc` or Python's `socket` module to verify that port 5432 is open on that IP from inside the Flask container.

**5.** Exec into the Postgres container and connect to the basketball database using `psql`.
List all tables. Query the players table directly with SQL. Then add a player using only SQL — no UI.

**6.** The Flask app logs are stored both inside the container and on the EC2 host.
Find both file paths. Confirm they are the same file by making a request and watching both locations update.

**7.** Stop the Flask container with `docker stop flask_app`. Watch what happens without doing anything else.
How long does it take to come back? What configuration controls this behavior and where is it set?

**8.** The Postgres container has a named Docker volume for its data. Find the volume name, inspect it,
and locate the directory on the EC2 host filesystem where Postgres is physically writing its data files.

**9.** The Postgres container is not exposed on any host port — you cannot connect to it directly from your laptop.
Without modifying docker-compose.yml, connect to the database using `psql` from the EC2 host.
What command lets you run `psql` without installing it on the host itself?

**10.** A deployment to a production system went wrong and you need to know exactly when each container was last
started or restarted. Find the start time of all three containers. Then check the docker daemon logs to see
if there were any container crash events in the last hour.

---

## Scripting Challenges

Write each script from scratch. No starter code. Test it against the running system.

**1.** `/opt/scripts/list_roster.sh`
Connect to the database from the EC2 host and print the full player roster as a formatted text table,
with column headers and aligned columns. The output should look clean when piped to `less`.

**2.** `/opt/scripts/watch_errors.sh`
Tail `/var/log/flaskapp/app.log` in real time. Print a highlighted alert line to stdout whenever
a log entry contains `500`. The script should run until interrupted with Ctrl-C.

**3.** `/opt/scripts/container_stats.sh`
For each of the three containers (postgres_db, flask_app, nginx_proxy), print the container name,
CPU usage percentage, and memory usage on a single line. Format the output so it is easy to read at a glance.

**4.** `/opt/scripts/db_query.sh`
Accept a player name (or partial name) as a command line argument.
Query the players table for any row where the name contains that string (case-insensitive).
Print the results. If no argument is given, print a usage message and exit with code 1.

**5.** `/opt/scripts/log_rotate.sh`
Copy `/var/log/flaskapp/app.log` to `/var/log/flaskapp/archive/` with a timestamp in the filename.
Then truncate the original file to zero bytes without deleting it or restarting the Flask container.
Print how many lines were in the log before rotation.
