# gateway2khair-test — EC2 infrastructure

This repository provisions a shared AWS EC2 server for developing and deploying the **school management project**. It is written for Muhammad, Ashur, and Sakib first — and for anyone else who needs to run or understand the same setup.

The stack creates a single app server in `us-east-1` with a locked-down security group: only named testers can reach SSH (22), HTTP (80), and HTTPS (443). Terraform state is stored in the existing S3 bucket `gateway2khair-test`.

## Tester assignments

Each person has a dedicated Terraform variable for their public IP. Use **CIDR notation** with `/32` for a single address (for example `203.0.113.10/32`).

| Person   | Terraform variable | Role    |
|----------|-------------------|---------|
| Muhammad | `tester1_ip`      | tester1 |
| Sakib    | `tester2_ip`      | tester2 |
| Ashur    | `tester3_ip`      | tester3 |

If your home or office IP changes, pass **your** variable again on the next `terraform apply` so the firewall rules follow you. You only ever need to set your own IP — the others stay at their defaults (`null`).

## What gets created

- One EC2 instance (`app-server`) in the default VPC
- A security group that allows inbound SSH, HTTP, and HTTPS only from configured tester IPs
- Outbound HTTP/HTTPS for package updates
- SSH access via the `ec2-key.pem` key pair (already registered in AWS)

## Prerequisites

Install these before you start:

1. **Terraform** 1.6 or newer — [install guide](https://developer.hashicorp.com/terraform/install)
2. **AWS CLI v2** — [install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
3. **Git** (to clone this repo)
4. **Bash** (macOS, Linux, or WSL on Windows)

You also need:

- AWS credentials with permission to create EC2 instances, security groups, and read/write the state bucket
- The **private half** of the `ec2-key.pem` SSH key (ask the project owner if you do not have it)

## 1. Configure the AWS CLI

Configure a named profile or the default profile with your access keys:

```bash
aws configure
```

You will be prompted for:

- AWS Access Key ID
- AWS Secret Access Key
- Default region: `us-east-1`
- Default output format: `json` (recommended)

Verify it works:

```bash
aws sts get-caller-identity
```

You should see your account ID and user/role ARN. If this fails, fix credentials before running Terraform.

## 2. Set up your SSH key (`setup-ec2-key.sh`)

The EC2 instance uses the AWS key pair named **`ec2-key.pem`**. This script installs the matching **private** key on your machine so you can SSH in.

From the project directory:

```bash
chmod +x setup-ec2-key.sh
./setup-ec2-key.sh
```

The script will:

1. Ask whether you are on **Mac** or **Linux / WSL**
2. Create `~/.ssh` if it does not exist (mode `700`)
3. If `~/.ssh/ec2-key.pem` already exists, ask whether to delete and replace it
4. Prompt you to **paste the private key** (paste the full key, then press **Enter**)
5. Write the private key to `~/.ssh/ec2-key.pem`
6. Add the key to your SSH agent (and macOS Keychain on Mac)

After this, you should be able to SSH using the key at `~/.ssh/ec2-key.pem`.

## 3. Initialize Terraform

Clone the repo and enter the directory:

```bash
git clone https://github.com/Muhammad-Ibra3/arabic-school-platform-test.git
cd arabic-school-platform-test
```

Initialize Terraform (downloads providers and configures the S3 backend):

```bash
terraform init
```

If you previously initialized with different backend settings:

```bash
terraform init -reconfigure
```

Continue to step 4 to set your tester IP and run `terraform apply`.

## 4. Set your tester IP and apply

All tester IP variables default to `null`, so you do **not** need a `terraform.tfvars` file. Each person passes **only their own** variable when running Terraform.

Find your current public IP:

```bash
curl -s https://checkip.amazonaws.com
```

Append `/32` to the result (for example `198.51.100.42/32`).

Use the `-var` flag that matches your name:

**Muhammad (tester1):**

```bash
terraform apply -var='tester1_ip=YOUR_PUBLIC_IP/32'
```

**Sakib (tester2):**

```bash
terraform apply -var='tester2_ip=YOUR_PUBLIC_IP/32'
```

**Ashur (tester3):**

```bash
terraform apply -var='tester3_ip=YOUR_PUBLIC_IP/32'
```

Replace `YOUR_PUBLIC_IP/32` with your actual address. Leave the other tester variables unset on your **first** apply.

**Working with teammates:** Terraform does not remember previous `-var` values. If someone else has already applied their IP, include their `-var` flags on your command as well so their firewall rules are not removed. For example, if Muhammad is already in and Sakib is applying:

```bash
terraform apply \
  -var='tester1_ip=MUHAMMAD_IP/32' \
  -var='tester2_ip=SAKIB_IP/32'
```

Review the plan (include your `-var` flag):

```bash
# Example for Muhammad:
terraform plan -var='tester1_ip=YOUR_PUBLIC_IP/32'
```

Apply the infrastructure:

```bash
# Example for Muhammad:
terraform apply -var='tester1_ip=YOUR_PUBLIC_IP/32'
```

Use `tester2_ip` or `tester3_ip` instead if you are Sakib or Ashur.

Type `yes` when prompted. When it finishes, note the outputs — especially `public_ip` and `ssh_connect_command`.

Connect to the server:

```bash
ssh -i ~/.ssh/ec2-key.pem ubuntu@<public_ip>
```

The default SSH user is `ubuntu` (matching the AMI in use). Use the `ssh_connect_command` output from Terraform if you prefer a copy-paste command.

## 5. Update your tester IP

When your public IP changes (new network, VPN, etc.):

1. Get your new IP: `curl -s https://checkip.amazonaws.com`
2. Run `terraform apply` again with **your** `-var` flag and the new CIDR:
   - Muhammad → `-var='tester1_ip=NEW_IP/32'`
   - Sakib → `-var='tester2_ip=NEW_IP/32'`
   - Ashur → `-var='tester3_ip=NEW_IP/32'`

```bash
# Example for Sakib after an IP change:
terraform apply -var='tester2_ip=NEW_IP/32'
```

Terraform updates the security group rules; you do not need to recreate the instance.

## 6. If `terraform apply` fails with a connection timeout

AWS API calls sometimes time out because of network blips, VPN issues, or a slow connection. The state file in S3 keeps track of what was already created, so you can usually **safely rerun** the same command (including your `-var` flag):

```bash
terraform apply -var='tester1_ip=YOUR_PUBLIC_IP/32'
```

If it still fails:

1. Check your internet connection and disable or change VPN if needed
2. Confirm AWS CLI still works: `aws sts get-caller-identity`
3. Run `terraform plan` and read which resource failed
4. Run `terraform apply` again

For a error that mentions **state lock**, wait a minute and retry — another apply may have been interrupted. If a lock persists in S3, ask the project owner before forcing an unlock.

Partial applies are normal: Terraform reconciles toward the desired state on the next successful run. You do not need to delete the instance and start over unless someone tells you the state is corrupted.

## Useful commands

| Command | Purpose |
|---------|---------|
| `terraform output` | Show instance IP, SSH command, allowed tester IPs |
| `terraform output ssh_connect_command` | Print the SSH command only |
| `terraform destroy` | Tear down all resources (use with care) |

## Project layout

| File | Purpose |
|------|---------|
| `main.tf` | EC2 instance, security group, variables, and outputs |
| `setup-ec2-key.sh` | Installs the `ec2-key.pem` private key locally |

## Security notes

- Inbound access is **deny by default**; only IPs passed via `tester1_ip`, `tester2_ip`, and `tester3_ip` can reach the server on ports 22, 80, and 443.
- Never commit private keys or AWS secret keys to git.

---

Questions about access or the `ec2-key.pem` key? Reach out to the project owner. Happy building.
