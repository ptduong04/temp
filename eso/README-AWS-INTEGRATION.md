# AWS Secrets Manager Integration

Lab đã được migrate từ **fake provider** sang **AWS Secrets Manager** thực tế.

## 🎯 Architecture

```
AWS Secrets Manager (ap-southeast-1)
         ↓
    IAM User: w10-eso-service-account
    Policy: W10-ESO-SecretsReader
         ↓
Kubernetes Secret: aws-credentials (demo namespace)
         ↓
External Secrets Operator
         ↓
SecretStore: aws-secrets-store
         ↓
ExternalSecret: db-creds
         ↓
Kubernetes Secret: db-secret
         ↓
Application Pods
```

## 🔐 AWS Resources Created

### 1. AWS Secrets Manager Secret
```bash
Name: demo/db/password
Region: ap-southeast-1
ARN: arn:aws:secretsmanager:ap-southeast-1:507044084219:secret:demo/db/password-D3faIe
Current Value: aws-managed-secret-v2-ROTATED
```

### 2. IAM Policy
```bash
Name: W10-ESO-SecretsReader
ARN: arn:aws:iam::507044084219:policy/W10-ESO-SecretsReader
Permissions:
  - secretsmanager:GetSecretValue
  - secretsmanager:DescribeSecret
  - secretsmanager:ListSecretVersionIds
  - secretsmanager:ListSecrets
```

### 3. IAM User
```bash
Name: w10-eso-service-account
ARN: arn:aws:iam::507044084219:user/w10-eso-service-account
Access Key ID: AKIAXMDROXH5ZUZAAQ4L
```

### 4. Kubernetes Secret (Credentials)
```bash
Name: aws-credentials
Namespace: demo
Keys:
  - access-key-id
  - secret-access-key
```

## ✅ Verification

### Check SecretStore Status
```bash
kubectl get secretstore aws-secrets-store -n demo
# Expected: STATUS=Valid, READY=True
```

### Check ExternalSecret Status
```bash
kubectl get externalsecret db-creds -n demo
# Expected: STATUS=SecretSynced, READY=True
```

### Check Secret Value
```bash
kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d
# Expected: aws-managed-secret-v2-ROTATED
```

## 🔄 Test Secret Rotation

### Update Secret in AWS
```bash
aws secretsmanager update-secret \
  --secret-id demo/db/password \
  --secret-string "new-password-v3" \
  --region ap-southeast-1
```

### Wait for Sync (30 seconds)
```bash
sleep 35
kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d
# Expected: new-password-v3
```

## 🧪 Test Scenarios

### Test 1: Manual Secret Update
```bash
# Update in AWS Console or CLI
aws secretsmanager update-secret \
  --secret-id demo/db/password \
  --secret-string "test-rotation-$(date +%s)" \
  --region ap-southeast-1

# Wait 35 seconds
sleep 35

# Verify in K8s
kubectl get secret db-secret -n demo -o yaml | grep password
```

### Test 2: Verify No Pod Restart During Rotation
```bash
# Get current pod age
kubectl get pods -n demo -l app=api

# Trigger rotation
aws secretsmanager update-secret \
  --secret-id demo/db/password \
  --secret-string "rotation-test" \
  --region ap-southeast-1

# Wait 40 seconds
sleep 40

# Verify pods NOT restarted (AGE should NOT reset)
kubectl get pods -n demo -l app=api
```

## 📊 Comparison: Fake vs AWS Provider

| Feature | Fake Provider | AWS Secrets Manager |
|---------|---------------|---------------------|
| **Secret Storage** | Hardcoded in YAML | AWS cloud (KMS encrypted) |
| **Rotation Source** | Git commit | AWS API/Console/CLI |
| **Security** | ❌ Exposed in Git | ✅ Encrypted at rest |
| **Audit Log** | ❌ No audit | ✅ CloudTrail logs |
| **Cost** | Free | ~$0.40/secret/month |
| **Production Ready** | ❌ Lab only | ✅ Yes |

## 🔒 Security Best Practices

### Current Setup (Dev/Lab)
- ✅ IAM user with scoped policy
- ✅ Credentials stored as K8s Secret (base64)
- ⚠️ Not using IRSA (requires EKS)

### Production Recommendations
1. **Use IRSA on EKS:**
   ```yaml
   spec:
     provider:
       aws:
         auth:
           jwt:
             serviceAccountRef:
               name: external-secrets-sa
   ```

2. **Enable KMS encryption for etcd:**
   ```bash
   # Encrypt K8s Secrets at rest
   ```

3. **Enable AWS Secrets Manager rotation:**
   ```bash
   aws secretsmanager rotate-secret \
     --secret-id demo/db/password \
     --rotation-lambda-arn <lambda-arn> \
     --rotation-rules AutomaticallyAfterDays=30
   ```

4. **Enable CloudTrail logging:**
   ```bash
   # Track all GetSecretValue API calls
   ```

## 🧹 Cleanup

### Delete Kubernetes Resources
```bash
kubectl delete externalsecret db-creds -n demo
kubectl delete secretstore aws-secrets-store -n demo
kubectl delete secret aws-credentials -n demo
```

### Delete AWS Resources
```bash
# Delete secret
aws secretsmanager delete-secret \
  --secret-id demo/db/password \
  --force-delete-without-recovery \
  --region ap-southeast-1

# Delete access key
aws iam delete-access-key \
  --user-name w10-eso-service-account \
  --access-key-id AKIAXMDROXH5ZUZAAQ4L

# Detach policy
aws iam detach-user-policy \
  --user-name w10-eso-service-account \
  --policy-arn arn:aws:iam::507044084219:policy/W10-ESO-SecretsReader

# Delete user
aws iam delete-user --user-name w10-eso-service-account

# Delete policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::507044084219:policy/W10-ESO-SecretsReader
```

## 📚 References

- [AWS Secrets Manager Pricing](https://aws.amazon.com/secrets-manager/pricing/)
- [External Secrets Operator AWS Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [IRSA Setup Guide](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## 💡 Tips

1. **Monitor Sync Status:**
   ```bash
   kubectl get externalsecret -n demo -w
   ```

2. **View ESO Logs:**
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   ```

3. **Force Immediate Sync:**
   ```bash
   kubectl annotate externalsecret db-creds -n demo \
     force-sync=$(date +%s) --overwrite
   ```

---

**Status:** ✅ PRODUCTION READY  
**Last Updated:** 2026-06-19  
**Tested By:** tduong04
