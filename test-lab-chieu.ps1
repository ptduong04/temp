# Test script cho Lab buổi chiều W10
# Chạy từng function để test từng phần

# Colors
function Write-Success { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Write-Test { param($msg) Write-Host "🧪 $msg" -ForegroundColor Yellow }

# ============================================
# SETUP FUNCTIONS
# ============================================

function Start-Cluster {
    Write-Info "Starting minikube cluster w10..."
    minikube start -p w10 --driver=docker --cpus=4 --memory=8192
    kubectl config use-context w10
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Cluster started successfully"
        kubectl get nodes
    } else {
        Write-Fail "Failed to start cluster"
        exit 1
    }
}

function Install-ArgoCD {
    Write-Info "Installing ArgoCD..."
    kubectl create ns argocd
    kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    Write-Info "Waiting for ArgoCD server..."
    kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "ArgoCD installed successfully"
    } else {
        Write-Fail "ArgoCD installation failed"
        exit 1
    }
}

function Get-ArgoCDPassword {
    Write-Info "Getting ArgoCD admin password..."
    $password = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    Write-Host ""
    Write-Host "=====================================`n" -ForegroundColor Yellow
    Write-Host "🔐 ArgoCD Credentials:`n" -ForegroundColor Green
    Write-Host "   URL:  https://localhost:8080" -ForegroundColor Cyan
    Write-Host "   User: admin" -ForegroundColor Cyan
    Write-Host "   Pass: $password`n" -ForegroundColor Cyan
    Write-Host "=====================================`n" -ForegroundColor Yellow
    
    Write-Info "Run in new terminal: kubectl -n argocd port-forward svc/argocd-server 8080:443"
}

function Deploy-AppOfApps {
    Write-Info "Deploying App of Apps..."
    kubectl apply -f argocd/root.yaml
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "App of Apps deployed"
        Start-Sleep -Seconds 5
        kubectl get applications -n argocd
    } else {
        Write-Fail "Failed to deploy App of Apps"
        exit 1
    }
}

function Wait-Infrastructure {
    Write-Info "Waiting for infrastructure components..."
    
    Write-Test "Waiting for Gatekeeper..."
    kubectl -n gatekeeper-system wait --for=condition=available --timeout=300s deployment/gatekeeper-controller-manager 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Success "Gatekeeper ready" } else { Write-Fail "Gatekeeper timeout" }
    
    Write-Test "Waiting for External Secrets..."
    kubectl -n external-secrets wait --for=condition=available --timeout=300s deployment/external-secrets 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Success "ESO ready" } else { Write-Fail "ESO timeout" }
    
    Write-Test "Waiting for Policy Controller..."
    kubectl -n cosign-system wait --for=condition=available --timeout=300s deployment/policy-controller-webhook 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Success "Policy Controller ready" } else { Write-Fail "Policy Controller timeout" }
    
    Write-Test "Waiting for Prometheus..."
    kubectl -n monitoring wait --for=condition=available --timeout=300s deployment/kube-prometheus-stack-operator 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Success "Prometheus ready" } else { Write-Fail "Prometheus timeout" }
}

function Show-AppStatus {
    Write-Info "ArgoCD Applications Status:"
    Write-Host ""
    kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
}

# ============================================
# LAB 2.1 - ESO TESTS
# ============================================

function Test-ESOBasic {
    Write-Test "Testing ESO basic functionality..."
    Write-Host ""
    
    # Check ESO pods
    Write-Info "Checking ESO pods..."
    kubectl get pods -n external-secrets
    
    # Check SecretStore
    Write-Info "Checking SecretStore..."
    kubectl get secretstore -n demo
    $storeStatus = kubectl get secretstore lab-fake-store -n demo -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
    if ($storeStatus -eq "True") {
        Write-Success "SecretStore is Ready"
    } else {
        Write-Fail "SecretStore not ready"
    }
    
    # Check ExternalSecret
    Write-Info "Checking ExternalSecret..."
    kubectl get externalsecret -n demo
    $esStatus = kubectl get externalsecret db-creds -n demo -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
    if ($esStatus -eq "True") {
        Write-Success "ExternalSecret is synced"
    } else {
        Write-Fail "ExternalSecret not synced"
    }
    
    # Check K8s Secret
    Write-Info "Checking Kubernetes Secret..."
    $secretValue = kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    Write-Host "Current secret value: $secretValue" -ForegroundColor Cyan
    
    if ($secretValue) {
        Write-Success "Secret exists and has value"
        return $secretValue
    } else {
        Write-Fail "Secret not found or empty"
        return $null
    }
}

function Test-SecretRotation {
    Write-Test "Testing Secret Rotation..."
    Write-Host ""
    
    # Get current value
    $oldValue = kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    Write-Info "Current value: $oldValue"
    
    # Get pod age before rotation
    Write-Info "Current pods in demo namespace:"
    kubectl get pods -n demo -l app=api -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp
    
    Write-Host ""
    Write-Host "=====================================`n" -ForegroundColor Yellow
    Write-Host "📝 MANUAL STEPS REQUIRED:`n" -ForegroundColor Cyan
    Write-Host "1. Edit eso/secret-store.yaml" -ForegroundColor White
    Write-Host "2. Change 'value: rotate-demo-v1' to 'value: rotate-demo-v2-CHANGED'" -ForegroundColor White
    Write-Host "3. Run: git add eso/secret-store.yaml" -ForegroundColor White
    Write-Host "4. Run: git commit -m 'test: rotate secret'" -ForegroundColor White
    Write-Host "5. Run: git push origin main" -ForegroundColor White
    Write-Host "6. Wait for ArgoCD to sync (~30s)" -ForegroundColor White
    Write-Host "7. Press Enter to verify..." -ForegroundColor White
    Write-Host "`n=====================================`n" -ForegroundColor Yellow
    
    Read-Host "Press Enter after you completed the steps above"
    
    # Wait a bit for sync
    Write-Info "Waiting 60 seconds for ESO to sync..."
    Start-Sleep -Seconds 60
    
    # Check new value
    $newValue = kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    Write-Info "New value: $newValue"
    
    if ($newValue -ne $oldValue) {
        Write-Success "Secret rotated successfully!"
    } else {
        Write-Fail "Secret not rotated (value unchanged)"
    }
    
    # Check if pods restarted
    Write-Info "Checking if pods restarted..."
    kubectl get pods -n demo -l app=api -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp
    
    Write-Host ""
    Write-Host "⚠️  Verify pods AGE - should be OLD (not restarted)" -ForegroundColor Yellow
}

# ============================================
# LAB 2.2 - SUPPLY CHAIN TESTS
# ============================================

function Test-PolicyController {
    Write-Test "Testing Policy Controller..."
    Write-Host ""
    
    # Check Policy Controller pods
    Write-Info "Checking Policy Controller pods..."
    kubectl get pods -n cosign-system
    
    # Check ClusterImagePolicy
    Write-Info "Checking ClusterImagePolicy..."
    kubectl get clusterimagepolicy
    
    $policyExists = kubectl get clusterimagepolicy w10-api-keyless 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "ClusterImagePolicy w10-api-keyless exists"
    } else {
        Write-Fail "ClusterImagePolicy not found"
    }
}

function Test-UnsignedImageReject {
    Write-Test "Testing unsigned image rejection..."
    Write-Host ""
    
    # Create temp file
    $testPod = @"
apiVersion: v1
kind: Pod
metadata:
  name: test-unsigned
  namespace: demo
spec:
  containers:
  - name: nginx
    image: nginx:1.27
"@
    
    $testPod | kubectl apply -f - 2>&1 | Tee-Object -Variable output
    
    if ($output -match "denied|rejected|failed policy") {
        Write-Success "Unsigned image REJECTED as expected ✅"
    } else {
        Write-Fail "Unsigned image was NOT rejected ❌"
    }
    
    # Cleanup
    kubectl delete pod test-unsigned -n demo --ignore-not-found 2>$null
}

function Test-SignedImagePass {
    Write-Test "Testing signed image (API rollout)..."
    Write-Host ""
    
    Write-Info "Checking API rollout..."
    kubectl get rollout api -n demo 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "API rollout exists and running (image is signed)"
        kubectl get rollout api -n demo -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.template.spec.containers[0].image
    } else {
        Write-Fail "API rollout not found or failed"
    }
}

# ============================================
# RBAC & GATEKEEPER TESTS (BONUS)
# ============================================

function Test-RBAC {
    Write-Test "Testing RBAC roles..."
    Write-Host ""
    
    # Test alice (developer)
    Write-Info "Testing alice (developer role)..."
    $result1 = kubectl auth can-i create deploy -n demo --as alice 2>$null
    if ($result1 -eq "yes") { Write-Success "alice can create deployments in demo ✅" } else { Write-Fail "alice cannot create deployments ❌" }
    
    $result2 = kubectl auth can-i create deploy -n kube-system --as alice 2>$null
    if ($result2 -eq "no") { Write-Success "alice cannot create in kube-system ✅" } else { Write-Fail "alice can create in kube-system ❌" }
    
    # Test bob (sre)
    Write-Info "Testing bob (sre role)..."
    $result3 = kubectl auth can-i get pods -A --as bob 2>$null
    if ($result3 -eq "yes") { Write-Success "bob can get pods cluster-wide ✅" } else { Write-Fail "bob cannot get pods ❌" }
    
    $result4 = kubectl auth can-i delete nodes --as bob 2>$null
    if ($result4 -eq "no") { Write-Success "bob cannot delete nodes ✅" } else { Write-Fail "bob can delete nodes ❌" }
    
    # Test carol (viewer)
    Write-Info "Testing carol (viewer role)..."
    $result5 = kubectl auth can-i get pods -A --as carol 2>$null
    if ($result5 -eq "yes") { Write-Success "carol can view pods ✅" } else { Write-Fail "carol cannot view pods ❌" }
    
    $result6 = kubectl auth can-i create pods -n demo --as carol 2>$null
    if ($result6 -eq "no") { Write-Success "carol cannot create pods ✅" } else { Write-Fail "carol can create pods ❌" }
}

function Test-Gatekeeper {
    Write-Test "Testing Gatekeeper policies..."
    Write-Host ""
    
    # Test 1: Image latest (should reject)
    Write-Info "Test 1: Rejecting image:latest..."
    kubectl apply -f gatekeeper/tests/pod-latest.yaml 2>&1 | Tee-Object -Variable out1
    if ($out1 -match "denied|rejected") { Write-Success "Rejected image:latest ✅" } else { Write-Fail "Did not reject image:latest ❌" }
    
    # Test 2: No limits (should reject)
    Write-Info "Test 2: Rejecting pod without limits..."
    kubectl apply -f gatekeeper/tests/pod-no-limits.yaml 2>&1 | Tee-Object -Variable out2
    if ($out2 -match "denied|rejected") { Write-Success "Rejected pod without limits ✅" } else { Write-Fail "Did not reject no-limits ❌" }
    
    # Test 3: Root user (should reject)
    Write-Info "Test 3: Rejecting root user..."
    kubectl apply -f gatekeeper/tests/pod-root-user.yaml 2>&1 | Tee-Object -Variable out3
    if ($out3 -match "denied|rejected") { Write-Success "Rejected root user ✅" } else { Write-Fail "Did not reject root user ❌" }
    
    # Test 4: Host network (should reject)
    Write-Info "Test 4: Rejecting host network..."
    kubectl apply -f gatekeeper/tests/pod-host-network.yaml 2>&1 | Tee-Object -Variable out4
    if ($out4 -match "denied|rejected") { Write-Success "Rejected host network ✅" } else { Write-Fail "Did not reject host network ❌" }
    
    # Test 5: No owner label (should reject)
    Write-Info "Test 5: Rejecting deployment without owner label..."
    kubectl apply -f gatekeeper/tests/deployment-no-owner.yaml 2>&1 | Tee-Object -Variable out5
    if ($out5 -match "denied|rejected") { Write-Success "Rejected no owner label ✅" } else { Write-Fail "Did not reject no owner ❌" }
    
    # Test 6: Valid pod (should pass)
    Write-Info "Test 6: Accepting valid pod..."
    kubectl apply -f gatekeeper/tests/pod-valid.yaml 2>&1 | Tee-Object -Variable out6
    if ($out6 -match "created") { Write-Success "Accepted valid pod ✅" } else { Write-Fail "Did not accept valid pod ❌" }
    
    # Test 7: Deployment with owner (should pass)
    Write-Info "Test 7: Accepting deployment with owner..."
    kubectl apply -f gatekeeper/tests/deployment-owner.yaml 2>&1 | Tee-Object -Variable out7
    if ($out7 -match "created") { Write-Success "Accepted deployment with owner ✅" } else { Write-Fail "Did not accept deployment ❌" }
    
    # Cleanup
    kubectl delete -f gatekeeper/tests/pod-valid.yaml --ignore-not-found 2>$null
    kubectl delete -f gatekeeper/tests/deployment-owner.yaml --ignore-not-found 2>$null
}

# ============================================
# MAIN MENU
# ============================================

function Show-Menu {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "   🧪 TEST LAB BUỔI CHIỀU W10" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SETUP:" -ForegroundColor Cyan
    Write-Host "  1. Start cluster + Install ArgoCD"
    Write-Host "  2. Get ArgoCD password"
    Write-Host "  3. Deploy App of Apps"
    Write-Host "  4. Wait for infrastructure"
    Write-Host "  5. Show ArgoCD app status"
    Write-Host ""
    Write-Host "LAB 2.1 - ESO:" -ForegroundColor Cyan
    Write-Host "  6. Test ESO basic"
    Write-Host "  7. Test Secret Rotation (manual steps)"
    Write-Host ""
    Write-Host "LAB 2.2 - SUPPLY CHAIN:" -ForegroundColor Cyan
    Write-Host "  8. Test Policy Controller"
    Write-Host "  9. Test unsigned image REJECT"
    Write-Host " 10. Test signed image PASS"
    Write-Host ""
    Write-Host "BONUS:" -ForegroundColor Cyan
    Write-Host " 11. Test RBAC (buổi sáng)"
    Write-Host " 12. Test Gatekeeper (buổi sáng)"
    Write-Host ""
    Write-Host "FULL AUTO:" -ForegroundColor Magenta
    Write-Host " 99. Run ALL tests (setup + all tests)"
    Write-Host ""
    Write-Host "  0. Exit"
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Yellow
}

function Run-AllTests {
    Write-Host "`n🚀 Running all tests...`n" -ForegroundColor Magenta
    
    Start-Cluster
    Install-ArgoCD
    Get-ArgoCDPassword
    
    Write-Info "Waiting 10 seconds before deploying apps..."
    Start-Sleep -Seconds 10
    
    Deploy-AppOfApps
    Wait-Infrastructure
    Show-AppStatus
    
    Write-Info "Waiting 30 seconds for apps to stabilize..."
    Start-Sleep -Seconds 30
    
    Test-ESOBasic
    Test-PolicyController
    Test-UnsignedImageReject
    Test-SignedImagePass
    Test-RBAC
    Test-Gatekeeper
    
    Write-Host "`n✅ All automated tests completed!`n" -ForegroundColor Green
    Write-Host "⚠️  Manual test: Secret Rotation (option 7)" -ForegroundColor Yellow
}

# Main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        1 { Start-Cluster; Install-ArgoCD }
        2 { Get-ArgoCDPassword }
        3 { Deploy-AppOfApps }
        4 { Wait-Infrastructure }
        5 { Show-AppStatus }
        6 { Test-ESOBasic }
        7 { Test-SecretRotation }
        8 { Test-PolicyController }
        9 { Test-UnsignedImageReject }
        10 { Test-SignedImagePass }
        11 { Test-RBAC }
        12 { Test-Gatekeeper }
        99 { Run-AllTests }
        0 { Write-Info "Exiting..."; exit 0 }
        default { Write-Fail "Invalid option" }
    }
    
    Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
    Read-Host
}
