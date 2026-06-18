# ⚡ QUICK TEST COMMANDS - Lab Buổi Chiều

## 🚀 1-MINUTE SETUP

```powershell
# Start cluster
minikube start -p w10 --driver=docker --cpus=4 --memory=8192
kubectl config use-context w10

# Install ArgoCD
kubectl create ns argocd
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server

# Deploy all apps
kubectl apply -f argocd/root.yaml
```

---

## 🔐 Lab 2.1 - ESO (5 phút)

### Check ESO đang chạy
```powershell
kubectl get pods -n external-secrets
kubectl get secretstore -n demo
kubectl get externalsecret -n demo
```

### Xem secret value hiện tại
```powershell
kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

### TEST: Rotate secret
```powershell
# 1. Edit file
notepad eso\secret-store.yaml
# Đổi value: rotate-demo-v1 → rotate-demo-v2-CHANGED

# 2. Git commit
git add eso/secret-store.yaml
git commit -m "test: rotate secret"
git push

# 3. Đợi 60s, check lại
Start-Sleep -Seconds 60
kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }

# 4. Verify pods KHÔNG restart
kubectl get pods -n demo -l app=api
```

**✅ Expected:** Value thay đổi, pods AGE không đổi

---

## 🔒 Lab 2.2 - Supply Chain (3 phút)

### Check Policy Controller
```powershell
kubectl get pods -n cosign-system
kubectl get clusterimagepolicy
```

### TEST 1: Unsigned image → REJECT
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

**✅ Expected:** `Error: admission webhook denied... failed policy`

### TEST 2: Signed image → PASS
```powershell
kubectl get rollout api -n demo
```

**✅ Expected:** Rollout running (image đã ký nên pass)

---

## 🎯 BONUS: Test RBAC (1 phút)

```powershell
# Alice (developer) - can create in demo
kubectl auth can-i create deploy -n demo --as alice
# Expected: yes

# Alice cannot create in kube-system
kubectl auth can-i create deploy -n kube-system --as alice
# Expected: no

# Bob (sre) - can view all pods
kubectl auth can-i get pods -A --as bob
# Expected: yes

# Bob cannot delete nodes
kubectl auth can-i delete nodes --as bob
# Expected: no

# Carol (viewer) - can view
kubectl auth can-i get pods -A --as carol
# Expected: yes

# Carol cannot create
kubectl auth can-i create pods -n demo --as carol
# Expected: no
```

---

## 🚧 BONUS: Test Gatekeeper (2 phút)

### REJECT tests (should all fail)
```powershell
kubectl apply -f gatekeeper/tests/pod-latest.yaml         # REJECT: image:latest
kubectl apply -f gatekeeper/tests/pod-no-limits.yaml      # REJECT: no limits
kubectl apply -f gatekeeper/tests/pod-root-user.yaml      # REJECT: root user
kubectl apply -f gatekeeper/tests/pod-host-network.yaml   # REJECT: host network
kubectl apply -f gatekeeper/tests/deployment-no-owner.yaml # REJECT: no owner label
```

**✅ Expected:** All rejected with "admission webhook denied"

### PASS tests (should succeed)
```powershell
kubectl apply -f gatekeeper/tests/pod-valid.yaml          # PASS
kubectl apply -f gatekeeper/tests/deployment-owner.yaml   # PASS
```

**✅ Expected:** `pod/test-valid created`, `deployment.apps/test-owner created`

### Cleanup
```powershell
kubectl delete -f gatekeeper/tests/pod-valid.yaml
kubectl delete -f gatekeeper/tests/deployment-owner.yaml
```

---

## 📊 Check Overall Status

```powershell
# ArgoCD apps
kubectl get applications -n argocd

# All namespaces
kubectl get all -n demo
kubectl get all -n external-secrets
kubectl get all -n cosign-system
kubectl get all -n gatekeeper-system

# Constraints
kubectl get constraints
```

---

## 🐛 Debug Commands

### ESO not syncing
```powershell
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
kubectl describe externalsecret db-creds -n demo
```

### Policy Controller rejecting wrong
```powershell
kubectl logs -n cosign-system -l app=policy-controller
kubectl describe clusterimagepolicy w10-api-keyless
```

### Gatekeeper not blocking
```powershell
kubectl logs -n gatekeeper-system -l control-plane=controller-manager
kubectl get constraint -o yaml
```

---

## 🧹 Cleanup

```powershell
# Delete apps
kubectl delete -f argocd/root.yaml

# Stop cluster
minikube stop -p w10

# Delete cluster
minikube delete -p w10
```

---

## 📋 CHECKLIST NGHIỆM THU

### Lab 2.1 - ESO
- [ ] ESO pods running
- [ ] SecretStore status: Valid
- [ ] ExternalSecret synced
- [ ] K8s Secret exists
- [ ] **Rotate test:** Value changes in <60s
- [ ] **Pods NOT restart** after rotation

### Lab 2.2 - Supply Chain
- [ ] Policy Controller running
- [ ] ClusterImagePolicy exists
- [ ] **Unsigned image:** REJECTED
- [ ] **Signed image:** PASS (rollout runs)

### BONUS
- [ ] RBAC: 6 tests pass (alice, bob, carol)
- [ ] Gatekeeper: 5 reject + 2 pass tests

---

## 🎉 Kết quả

Sau khi test xong:

✅ **ESO:** Secret rotation < 60s, no restart  
✅ **Supply Chain:** Only signed images allowed  
✅ **RBAC:** Role-based access works  
✅ **Gatekeeper:** Policies enforced  
✅ **GitOps:** Everything via Git  

**🚀 Production-ready platform!**
