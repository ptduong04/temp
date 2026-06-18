# 🧪 HƯỚNG DẪN TEST LAB BUỔI CHIỀU W10

## 📋 Prerequisites

Đảm bảo đã cài:
- ✅ Docker Desktop running
- ✅ kubectl
- ✅ minikube

---

## 🚀 BƯỚC 1: Setup Cluster & ArgoCD

### 1.1. Start minikube cluster
```powershell
minikube start -p w10 --driver=docker --cpus=4 --memory=8192
kubectl config use-context w10
```

### 1.2. Verify cluster
```powershell
kubectl get nodes
kubectl cluster-info
```

### 1.3. Install ArgoCD
```powershell
kubectl create ns argocd
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Đợi ArgoCD ready (~2-3 phút)
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server
```

### 1.4. Get ArgoCD password
```powershell
# Lấy password
$password = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
Write-Host "ArgoCD Password: $password"

# Port forward ArgoCD UI (mở terminal mới)
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

**💡 Truy cập ArgoCD UI:**
- URL: https://localhost:8080
- User: `admin`
- Pass: (password từ lệnh trên)
- Accept certificate warning

---

## 📦 BƯỚC 2: Deploy Infrastructure qua GitOps

### 2.1. Deploy App of Apps
```powershell
kubectl apply -f argocd/root.yaml
```

### 2.2. Xem ArgoCD sync progress
```powershell
# List tất cả apps
kubectl get applications -n argocd

# Hoặc xem trên UI: https://localhost:8080
```

### 2.3. Đợi infrastructure ready (~5-10 phút)
```powershell
# Check Gatekeeper
kubectl -n gatekeeper-system wait --for=condition=available --timeout=300s deployment/gatekeeper-controller-manager

# Check ESO
kubectl -n external-secrets wait --for=condition=available --timeout=300s deployment/external-secrets

# Check Policy Controller (Cosign)
kubectl -n cosign-system wait --for=condition=available --timeout=300s deployment/policy-controller-webhook

# Check Prometheus
kubectl -n monitoring wait --for=condition=available --timeout=300s deployment/kube-prometheus-stack-operator
```

### 2.4. Verify all apps synced
```powershell
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'
```

**Expect:** Tất cả apps có status `Synced` và `Healthy`

---

## 🔐 BƯỚC 3: Test Lab 2.1 - ESO (Secret Rotation)

### 3.1. Verify ESO đang chạy
```powershell
# Check ESO pods
kubectl get pods -n external-secrets

# Check SecretStore
kubectl get secretstore -n demo
kubectl describe secretstore lab-fake-store -n demo

# Check ExternalSecret
kubectl get externalsecret -n demo
kubectl describe externalsecret db-creds -n demo
```

**✅ Expected:**
- ESO pod: Running
- SecretStore: Valid
- ExternalSecret: SecretSynced = True

### 3.2. Verify K8s Secret được tạo tự động
```powershell
# List secrets
kubectl get secret -n demo

# Xem giá trị secret hiện tại
kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

**✅ Expected:** Output = `rotate-demo-v1`

### 3.3. **TEST ROTATION** - Đổi giá trị secret

**Step 1:** Edit SecretStore
```powershell
# Mở file
notepad eso\secret-store.yaml
```

**Thay đổi dòng 14:**
```yaml
# TRƯỚC:
        value: rotate-demo-v1

# SAU:
        value: rotate-demo-v2-CHANGED
```

**Step 2:** Commit & push
```powershell
git add eso/secret-store.yaml
git commit -m "test: rotate secret to v2"
git push origin main
```

**Step 3:** Đợi ArgoCD sync (hoặc sync manual trên UI)
```powershell
# Xem sync status
kubectl get application eso-config -n argocd -w

# Hoặc force sync
argocd app sync eso-config --grpc-web
```

**Step 4:** Verify K8s Secret tự động cập nhật (< 60s)
```powershell
# Đợi 30-60 giây, sau đó check
kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

**✅ Expected:** Output = `rotate-demo-v2-CHANGED`

### 3.4. **NGHIỆM THU:** Verify pods KHÔNG restart
```powershell
# List pods và xem AGE
kubectl get pods -n demo -l app=api

# Xem pod events
kubectl get events -n demo --sort-by='.lastTimestamp' | Select-String -Pattern "api"
```

**✅ Expected:**
- Pod AGE vẫn giữ nguyên (không restart)
- Không có event "Killing" hay "Started"

### 3.5. Bonus: Xem secret được mount vào pod
```powershell
# Exec vào pod
$podName = kubectl get pod -n demo -l app=api -o jsonpath='{.items[0].metadata.name}'
kubectl exec -it $podName -n demo -- cat /var/run/secrets/db/password
```

**✅ Expected:** File content = `rotate-demo-v2-CHANGED`

---

## 🔒 BƯỚC 4: Test Lab 2.2 - Supply Chain (Trivy + Cosign)

### 4.1. Verify Policy Controller đang chạy
```powershell
# Check pods
kubectl get pods -n cosign-system

# Check ClusterImagePolicy
kubectl get clusterimagepolicy
kubectl describe clusterimagepolicy w10-api-keyless
```

**✅ Expected:**
- Policy controller: Running
- ClusterImagePolicy: w10-api-keyless exists

### 4.2. **TEST CASE 1:** Image CHƯA ký → REJECT

**Tạo test manifest:**
```powershell
@"
apiVersion: v1
kind: Pod
metadata:
  name: test-unsigned
  namespace: demo
spec:
  containers:
  - name: nginx
    image: nginx:1.27
"@ | kubectl apply -f -
```

**✅ Expected:** Pod bị REJECT với error:
```
Error: admission webhook denied the request: 
validation failed: failed policy: w10-api-keyless
```

### 4.3. **TEST CASE 2:** Image ĐÃ ký → PASS

**Giả sử bạn đã build & sign image qua GitHub Actions.**

Nếu chưa, có thể test với image public đã ký:
```powershell
# Test với image đã ký từ repo của bạn
# (Cần đổi image trong rollout.yaml trước)
kubectl get rollout api -n demo
```

**✅ Expected:** Rollout deploy thành công

### 4.4. **TEST TRIVY SCAN** - Xem GitHub Actions

**Bước 1:** Push code change để trigger CI
```powershell
# Sửa file bất kỳ trong src/api/
notepad src\api\app.py

# Thêm comment hoặc thay đổi nhỏ, sau đó:
git add src/api/app.py
git commit -m "test: trigger CI pipeline"
git push origin main
```

**Bước 2:** Xem GitHub Actions workflow
- Truy cập: https://github.com/[your-username]/temp/actions
- Xem workflow "Build and Push Image"
- Check job steps:
  1. ✅ Build image
  2. ✅ **Trivy scan** (HIGH/CRITICAL)
  3. ✅ Push image
  4. ✅ **Cosign sign** (keyless)
  5. ✅ Update rollout.yaml

**✅ Expected:**
- Trivy scan: PASS (no HIGH/CRITICAL CVEs)
- Cosign sign: Success
- Git commit: Auto-update version trong rollout.yaml

### 4.5. **TEST TRIVY FAIL** - Image có CVE

**Để test Trivy fail, cần:**
1. Build image với base image có CVE HIGH/CRITICAL
2. Workflow sẽ fail tại step "Scan image with Trivy"
3. Image không được push

*(Lab này khó test local, chủ yếu demo qua slide)*

### 4.6. Verify image signature bằng Cosign CLI (Optional)

**Install Cosign:**
```powershell
# Download từ: https://github.com/sigstore/cosign/releases
# Hoặc dùng chocolatey:
choco install cosign
```

**Verify signature:**
```powershell
# Lấy image từ rollout
$image = kubectl get rollout api -n demo -o jsonpath='{.spec.template.spec.containers[0].image}'
Write-Host "Image: $image"

# Verify keyless signature
cosign verify $image `
  --certificate-identity-regexp "https://github.com/.*/temp/.github/workflows/build-push.yml@refs/heads/main" `
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

**✅ Expected:** Signature verified successfully với Rekor log

---

## 📊 BƯỚC 5: Verify Toàn Bộ Stack

### 5.1. Check tất cả namespaces
```powershell
kubectl get all -n demo
kubectl get all -n monitoring
kubectl get all -n gatekeeper-system
kubectl get all -n external-secrets
kubectl get all -n cosign-system
```

### 5.2. Check Gatekeeper constraints
```powershell
kubectl get constraints

# Verify enforced policies
kubectl get k8sdisallowedimagetags
kubectl get k8srequiredlabels
kubectl get k8srequiredresourcelimits
kubectl get k8sdisallowrootuser
kubectl get k8sdisallowhostnetwork
```

### 5.3. Check RBAC (từ buổi sáng)
```powershell
# Test quyền alice (developer)
kubectl auth can-i create deploy -n demo --as alice
# Expected: yes

kubectl auth can-i create deploy -n kube-system --as alice
# Expected: no

# Test quyền bob (sre)
kubectl auth can-i get pods -A --as bob
# Expected: yes

kubectl auth can-i delete nodes --as bob
# Expected: no

# Test quyền carol (viewer)
kubectl auth can-i get pods -A --as carol
# Expected: yes

kubectl auth can-i create pods -n demo --as carol
# Expected: no
```

### 5.4. Test Gatekeeper policies
```powershell
# Test reject: image latest
kubectl apply -f gatekeeper/tests/pod-latest.yaml
# Expected: Error (denied by policy)

# Test reject: no limits
kubectl apply -f gatekeeper/tests/pod-no-limits.yaml
# Expected: Error (denied by policy)

# Test reject: root user
kubectl apply -f gatekeeper/tests/pod-root-user.yaml
# Expected: Error (denied by policy)

# Test reject: host network
kubectl apply -f gatekeeper/tests/pod-host-network.yaml
# Expected: Error (denied by policy)

# Test reject: no owner label
kubectl apply -f gatekeeper/tests/deployment-no-owner.yaml
# Expected: Error (denied by policy)

# Test PASS: valid pod
kubectl apply -f gatekeeper/tests/pod-valid.yaml
# Expected: pod/test-valid created

# Test PASS: deployment with owner
kubectl apply -f gatekeeper/tests/deployment-owner.yaml
# Expected: deployment.apps/test-owner created

# Cleanup
kubectl delete -f gatekeeper/tests/pod-valid.yaml
kubectl delete -f gatekeeper/tests/deployment-owner.yaml
```

---

## 🎯 CHECKLIST NGHIỆM THU BUỔI CHIỀU

### **Lab 2.1 - ESO:**
- [ ] ESO pods running
- [ ] SecretStore status: Valid
- [ ] ExternalSecret status: SecretSynced
- [ ] K8s Secret `db-secret` được tạo tự động
- [ ] **Đổi giá trị trong SecretStore** → K8s Secret tự update < 60s
- [ ] **Pods KHÔNG restart** khi secret thay đổi
- [ ] Secret được mount vào pod tại `/var/run/secrets/db/password`

### **Lab 2.2 - Supply Chain:**
- [ ] Policy Controller pods running
- [ ] ClusterImagePolicy `w10-api-keyless` exists
- [ ] **Test unsigned image** → bị REJECT
- [ ] **Test signed image** → PASS (API rollout chạy được)
- [ ] GitHub Actions workflow:
  - [ ] Trivy scan pass (no HIGH/CRITICAL)
  - [ ] Cosign sign success
  - [ ] Auto-update rollout.yaml với version mới
- [ ] (Optional) Verify signature bằng Cosign CLI

### **Bonus - Stack hoàn chỉnh:**
- [ ] RBAC: 3 roles test pass (alice, bob, carol)
- [ ] Gatekeeper: 5 constraints enforce
- [ ] Gatekeeper tests: 5 reject + 2 pass
- [ ] ArgoCD: 14 apps synced & healthy
- [ ] Prometheus: Metrics đang scrape

---

## 🐛 Troubleshooting

### ESO không sync secret
```powershell
# Check logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Describe ExternalSecret
kubectl describe externalsecret db-creds -n demo

# Force refresh
kubectl annotate externalsecret db-creds -n demo force-sync="$(date +%s)" --overwrite
```

### Policy Controller reject image đúng
```powershell
# Check logs
kubectl logs -n cosign-system -l app=policy-controller

# Describe ClusterImagePolicy
kubectl describe clusterimagepolicy w10-api-keyless

# Check admission webhook
kubectl get validatingwebhookconfigurations | Select-String cosign
```

### Gatekeeper không chặn
```powershell
# Check Gatekeeper audit logs
kubectl logs -n gatekeeper-system -l control-plane=audit-controller

# Check constraint status
kubectl get constraint <constraint-name> -o yaml

# Verify webhook
kubectl get validatingwebhookconfigurations | Select-String gatekeeper
```

### ArgoCD app OutOfSync
```powershell
# Xem diff
argocd app diff <app-name> --grpc-web

# Force sync
argocd app sync <app-name> --grpc-web --force

# Hoặc dùng UI
```

---

## 🧹 Cleanup

### Xóa test resources
```powershell
kubectl delete -f gatekeeper/tests/ --ignore-not-found
```

### Xóa toàn bộ lab
```powershell
# Delete ArgoCD apps
kubectl delete -f argocd/root.yaml

# Đợi resources cleanup
Start-Sleep -Seconds 30

# Delete ArgoCD
kubectl delete ns argocd

# Stop cluster
minikube stop -p w10
```

### Xóa cluster hoàn toàn
```powershell
minikube delete -p w10
```

---

## 📚 Tham khảo

- **ESO Docs:** https://external-secrets.io
- **Trivy:** https://trivy.dev
- **Cosign:** https://docs.sigstore.dev/cosign/overview
- **Gatekeeper:** https://open-policy-agent.github.io/gatekeeper
- **ArgoCD:** https://argo-cd.readthedocs.io

---

## 🎉 Kết quả mong đợi

Sau khi test xong, bạn sẽ có:

1. ✅ **ESO:** Secret rotation < 60s không restart pod
2. ✅ **Supply Chain:** Image phải scan + ký mới deploy được
3. ✅ **RBAC:** 3 roles phân quyền chính xác
4. ✅ **Gatekeeper:** 5 policies enforce, reject manifest xấu
5. ✅ **GitOps:** Tất cả qua Git, không kubectl apply tay
6. ✅ **Observability:** Prometheus + AlertManager + Grafana (từ W9)
7. ✅ **Canary:** Argo Rollouts với auto-analysis (từ W9)

**🚀 Cluster production-ready cho W11-W12 Capstone!**
