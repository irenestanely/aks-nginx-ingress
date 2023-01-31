helm upgrade --install nginx-ingress-test ingress-nginx/ingress-nginx --namespace $SERVICE_ACCOUNT_NAMESPACE --set controller.replicaCount=1 --set serviceAccount.create=false --set secrets-store-csi-driver.enableSecretRotation=true --set serviceAccount.name=$SERVICE_ACCOUNT_NAME --set controller.nodeSelector."kubernetes\.io/os"=linux --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
-f - <<EOF
controller:
  extraVolumes:
      - name: "tls-secret-store"
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "azure-sprovider-wi"
  extraVolumeMounts:
      - name: "tls-secret-store"
        mountPath: "/mnt/secrets-store"
        readOnly: true
EOF
