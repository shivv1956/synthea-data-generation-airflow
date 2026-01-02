# GitHub Secrets Setup Guide

To enable CI/CD deployment with GitHub Actions, you need to configure the following secrets in your GitHub repository.

## 📋 Required Secrets

Navigate to: **Repository Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### AWS Credentials

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCY` |
| `AWS_REGION` | AWS Region | `us-east-1` |
| `AWS_S3_BUCKET` | S3 Bucket Name | `synthea-patient-data` |
| `AWS_S3_PREFIX` | S3 Key Prefix | `raw/fhir` |

### Application Settings

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `ENABLE_TRANSFORMATIONS` | Enable data transformations | `false` |

## 🔐 How to Add Secrets

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Enter the secret name and value
5. Click **Add secret**
6. Repeat for all required secrets

## 🧪 Test Your Setup

1. Push to `main` or `develop` branch
2. Go to **Actions** tab in GitHub
3. Watch the workflow run
4. Check for successful deployment

## 🔄 Local Development

For local development, copy `.env.example` to `.env` and fill in your actual values:

```bash
cp .env.example .env
# Edit .env with your credentials
```

**Never commit `.env` to git!** It's already in `.gitignore`.

## 🚀 Deployment Workflow

The GitHub Actions workflow will:
1. ✅ Checkout code
2. ✅ Create `.env` from secrets
3. ✅ Build Docker images
4. ✅ Run tests (optional)
5. ✅ Deploy to server
6. ✅ Run health checks
7. ✅ Send notifications

## 📝 CI Test Workflow

The CI test workflow will:
1. ✅ Lint Python code (black, flake8)
2. ✅ Validate DAG syntax
3. ✅ Check Docker Compose configuration
4. ✅ Build Docker images
5. ✅ Run integration tests
6. ✅ Scan for hardcoded secrets

## 🔒 Security Best Practices

- ✅ Never commit `.env` to version control
- ✅ Use `.env.example` for documentation
- ✅ Rotate credentials regularly
- ✅ Use least-privilege IAM policies
- ✅ Enable MFA on AWS accounts
- ✅ Use AWS IAM roles when possible (EC2/ECS)

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Encrypted Secrets Guide](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## 🆘 Troubleshooting

### Secrets not working
- Verify secret names match exactly (case-sensitive)
- Check workflow syntax for correct secret access: `${{ secrets.SECRET_NAME }}`
- Ensure secrets are set at repository level, not environment level

### Build failures
- Check workflow logs in Actions tab
- Verify Docker Compose syntax locally
- Test DAG files for syntax errors

### Deployment issues
- Verify server access credentials
- Check firewall rules
- Review deployment logs in workflow runs
