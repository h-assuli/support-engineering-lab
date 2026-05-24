#!/bin/bash
set -e

IMAGE_NAME=${1:-hello-web}
TAG=${2:-1.0}
NAMESPACE=${3:-demo}
DEPLOYMENT=${4:-hello-deploy}

echo "================================================"
echo " Build & Deploy: ${IMAGE_NAME}:${TAG} -> ${NAMESPACE}"
echo "================================================"

# Step 1: Build WAR
echo ""
echo "[1/5] Building WAR with Maven..."
mvn -q clean package
if [ ! -f target/${IMAGE_NAME}.war ]; then
  echo "ERROR: WAR file not produced!"
  exit 1
fi
echo "      WAR built: $(ls -lh target/${IMAGE_NAME}.war | awk '{print $5}')"

# Step 2: Build Docker image
echo ""
echo "[2/5] Building Docker image..."
docker build -q -t ${IMAGE_NAME}:${TAG} . > /dev/null
echo "      Image built: ${IMAGE_NAME}:${TAG}"

# Step 3: Load into minikube
echo ""
echo "[3/5] Loading image into minikube..."
minikube image load ${IMAGE_NAME}:${TAG}
echo "      Image loaded into cluster"

# Step 4: Trigger rolling update
echo ""
echo "[4/5] Rolling update of deployment..."
# Force restart by patching annotation (works even if image tag unchanged)
kubectl -n ${NAMESPACE} patch deployment ${DEPLOYMENT} \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"redeployed-at\":\"$(date +%s)\"}}}}}"
kubectl -n ${NAMESPACE} set image deployment/${DEPLOYMENT} hello=${IMAGE_NAME}:${TAG} || true
kubectl -n ${NAMESPACE} rollout status deployment/${DEPLOYMENT} --timeout=120s

# Step 5: Verify
echo ""
echo "[5/5] Verifying endpoint..."
URL=$(minikube service hello-svc -n ${NAMESPACE} --url)
sleep 3
RESPONSE=$(curl -s ${URL}/hello-web/)
echo "      URL: ${URL}/hello-web/"
echo "      Response: ${RESPONSE}"

if echo "${RESPONSE}" | grep -q "Hello from Tomcat"; then
  echo ""
  echo "================================================"
  echo " DEPLOYMENT SUCCESSFUL"
  echo "================================================"
else
  echo ""
  echo "================================================"
  echo " DEPLOYMENT VERIFICATION FAILED"
  echo "================================================"
  kubectl get pods -n ${NAMESPACE}
  exit 1
fi
