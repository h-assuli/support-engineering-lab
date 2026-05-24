# hello-web Runbook

## System Overview
- **App**: hello-web (Java Servlet on Tomcat 9 + JDK 11)
- **Database**: Oracle XE 21c (Docker container `oraclexe`)
- **Orchestration**: Kubernetes (minikube) in namespace `demo`
- **Service**: NodePort `hello-svc` exposing port 8080

## 1. Quick Health Check
```bash
# Pods
kubectl get pods -n demo
# Service URL
minikube service hello-svc -n demo --url
# Endpoint test
curl $(minikube service hello-svc -n demo --url)/hello-web/
# Database
docker ps --filter name=oraclexe
```
Expected: pods `Running 1/1`, curl returns "Hello from Tomcat in container".

## 2. Log Locations
```bash
# Pod logs
kubectl logs -f <pod> -n demo
# Previous (crashed) container logs
kubectl logs <pod> -n demo --previous
# Oracle logs
docker logs oraclexe --tail 50
```

## 3. Common Issues

### Issue A: Pod not Ready (CrashLoopBackOff / ImagePullBackOff)
```bash
kubectl describe pod <pod> -n demo
kubectl logs <pod> -n demo --previous
```
- **ImagePullBackOff** -> wrong image tag. Fix: `kubectl set image deployment/hello-deploy hello=hello-web:<correct-tag> -n demo`
- **CrashLoopBackOff** -> app crashing. Check logs, fix code, rebuild, redeploy.

### Issue B: Service returns 5xx or hangs
```bash
# Thread dump for hung Java
POD=$(kubectl get pod -n demo -l app=hello -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n demo -- jstack 1 > /tmp/threaddump.txt
# Heap info
kubectl exec $POD -n demo -- jmap -heap 1
# Restart pod
kubectl delete pod $POD -n demo
```

### Issue C: Database connection failure
```bash
# Check Oracle is running
docker ps --filter name=oraclexe
# Check ready
docker logs oraclexe 2>&1 | grep "READY TO USE"
# Test connect as app
docker exec -i oraclexe sqlplus -s app/app@XEPDB1 <<< "SELECT 1 FROM dual; EXIT;"
# If user locked
docker exec -i oraclexe sqlplus -s sys/Oracle123@//localhost:1521/XEPDB1 as sysdba <<EOS
ALTER USER app ACCOUNT UNLOCK;
ALTER USER app IDENTIFIED BY app;
EXIT;
EOS
```

## 4. Deployment Operations

### Rollback bad deploy
```bash
kubectl rollout undo deployment/hello-deploy -n demo
kubectl rollout status deployment/hello-deploy -n demo
```

### Restart all pods (clean restart)
```bash
kubectl rollout restart deployment/hello-deploy -n demo
```

### Scale up under load
```bash
kubectl scale deployment/hello-deploy --replicas=3 -n demo
```

## 5. Database Backup / Restore

### Backup (Data Pump)
```bash
docker exec oraclexe expdp app/app@XEPDB1 schemas=app directory=DATA_PUMP_DIR dumpfile=app_backup.dmp logfile=app_backup.log reuse_dumpfiles=Y
```

### Restore single table
```bash
docker exec oraclexe impdp app/app@XEPDB1 directory=DATA_PUMP_DIR dumpfile=app_backup.dmp tables=app.employees
```

## 6. Escalation
- **L1 / On-call**: <fill in>
- **DBA**: <fill in>
- **Platform / K8s team**: <fill in>
- **Slack**: #support-engineers
