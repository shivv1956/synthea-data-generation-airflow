# GitHub Actions Workflows

This directory contains CI/CD workflows for the Synthea HAPI Server project.

## 📁 Workflows

### 1. `test.yml` - Continuous Integration
**Trigger:** Push/PR to `main` or `develop` branches

**Jobs:**
- Lint Python code (black, flake8)
- Validate DAG syntax
- Check Docker Compose configuration
- Build Docker images
- Run integration tests
- Security scan for hardcoded credentials

### 2. `deploy.yml` - Continuous Deployment
**Trigger:** Push to `main` or `develop` branches, or manual trigger

**Jobs:**
- Create `.env` from GitHub Secrets
- Build Docker images
- Run tests
- Deploy to server (customize for your infrastructure)
- Health checks
- Send notifications

## 🔧 Setup Required

1. **Configure GitHub Secrets** (see [SECRETS_SETUP.md](../SECRETS_SETUP.md))
   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY
   - AWS_REGION
   - AWS_S3_BUCKET
   - AWS_S3_PREFIX
   - ENABLE_TRANSFORMATIONS

2. **Customize Deployment** (in `deploy.yml`)
   - Update the "Deploy to production server" step
   - Add your SSH commands, server details, etc.

3. **Optional: Add Notifications**
   - Slack webhook
   - Discord webhook
   - Email notifications

## 🚀 Usage

### Automatic Triggers
- Push to `main` or `develop` → Runs both test and deploy workflows
- Create PR → Runs test workflow only

### Manual Trigger
Go to **Actions** tab → Select "Deploy Synthea HAPI Server" → Click "Run workflow"

## 📊 Status Badges

Add to your README.md:

```markdown
![CI Tests](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/test.yml/badge.svg)
![Deploy](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/deploy.yml/badge.svg)
```

## 🛠️ Customization

### Change Python version
Edit `test.yml`:
```yaml
python-version: '3.11'  # Change to '3.12', etc.
```

### Add more linters
Edit `test.yml`:
```yaml
- name: Run mypy
  run: mypy dags/
```

### Modify deployment target
Edit `deploy.yml`:
```yaml
- name: Deploy to production server
  run: |
    ssh user@server 'cd /app && docker-compose up -d'
```

## 📝 Notes

- Workflows run on Ubuntu latest by default
- Docker Buildx is used for multi-platform builds
- Secrets are encrypted and never exposed in logs
- Failed workflows will send email notifications to commit author
