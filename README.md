# AKS Cluster with Nginx Ingress Controller

This contains sample specs of securing an NGINX Ingress Controller with TLS with an Azure Kubernetes Service (AKS) cluster and an Azure Key Vault (AKV) instance. For more information, see [csi-secrets-store-nginx-tls]([csi-secrets-store-nginx-tls](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-nginx-tls)).

Similar to Kubernetes secrets, on pod start and restart, the Secrets Store CSI driver communicates with the provider using gRPC to retrieve the secret content from the external Secrets Store specified in the SecretProviderClass custom resource. Then the volume is mounted in the pod as tmpfs and the secret contents are written to the volume.

The [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/concepts.html) on Azure Kubernetes Service (AKS) provides a variety of methods of identity-based access to your Azure key vault. In this example we have used AKS with Azure AD WorkloadIdentity (preview) to access the Azure resources.

The Secrets Store CSI driver secrets-store.csi.k8s.io allows Kubernetes to mount multiple secrets, keys, and certs stored in enterprise-grade external secrets stores into their pods as a volume. Once the Volume is attached, the data in it is mounted into the container's file system.

## Prerequisites 

Please install the below in your operating system and use the same resource group for the below steps

1. [Helm 3](https://helm.sh/docs/intro/install/) 
2. [AKS cluster(latest)](https://learn.microsoft.com/en-us/azure/aks/learn/quick-kubernetes-deploy-cli) 
3. [Azure Keyvault](https://learn.microsoft.com/en-us/azure/key-vault/general/quick-create-portal)


## Installation 

Please substitute the necessary placeholder values in the below steps

### Kubeconfig Setup

```bash
az aks get-credentials --resource-group <resource_group_of_aks> --name <aks_cluster_name> --file ~/.kube_config
```

### Enable Managed Identity in AKS

```bash
az aks update --enable-managed-identity --resource-group <resource_group_of_aks> --name <aks_cluster_name>
```

### Register WorkloadIdentityPreview and enableoidcissuer

```bash
az feature register --name EnableWorkloadIdentityPreview --namespace Microsoft.ContainerService

az provider register -n Microsoft.ContainerService

az aks update -n <aks_cluster_name> -g <resource_group_of_aks> --enable-oidc-issuer

export AKS_OIDC_ISSUER="$(az aks show --resource-group <resource_group_of_aks> --name <aks_cluster_name> --query "oidcIssuerProfile.issuerUrl" -o tsv)"

echo $AKS_OIDC_ISSUER
```

### Create Managed Identity

```bash
 az identity create --name <identity_name> --resource-group <resource_group_of_aks>

export USER_ASSIGNED_CLIENT_ID="$(az identity show -g <resource_group_of_aks> --name <identity_name> --query 'clientId' -o tsv)"

export IDENTITY_TENANT=$(az aks show --name <aks_cluster_name> --resource-group <resource_group_of_aks>  --query aadProfile.tenantId -o tsv)

```

### Set Access for Identity to access keyvault(created from prerequisites)

```bash
az keyvault set-policy -n <key_vault_name_from_prerequisites> --key-permissions get --spn $USER_ASSIGNED_CLIENT_ID

az keyvault set-policy -n <key_vault_name_from_prerequisites> --secret-permissions get --spn $USER_ASSIGNED_CLIENT_ID

az keyvault set-policy -n <key_vault_name_from_prerequisites> --certificate-permissions get --spn $USER_ASSIGNED_CLIENT_ID
```

### AKS Service account and FederatedIdentity creation

```bash
export serviceAccountName="workload-identity-sa"
export serviceAccountNamespace="default"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
  labels:
    azure.workload.identity/use: "true"
  name: ${serviceAccountName}
  namespace: ${serviceAccountNamespace}
EOF

export federatedIdentityName="aksfederatedidentity"

az identity federated-credential create --name $federatedIdentityName --identity-name <identity_name>  --resource-group <resource_group_of_aks> --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${serviceAccountNamespace}:${serviceAccountName}
```

### Nginx Ingress

Install the below after successful aks cluster installation

```bash
# add the helm chart
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
kubectl create ns ingress
# install the nginx ingress
helm install my-release nginx-stable/nginx-ingress
```

### Cert creation and import to azure keyvault

After the helm chart installation, follow the below steps for cert creation

```bash
KEY_PATH="aks-ingress-tls.key"
CERT_PATH="aks-ingress-tls.crt"
CERT_WITH_KEY_PATH="aks-ingress-tls-withkey.pem"
HOST_NAME="<Your Host>"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $KEY_PATH -out $CERT_PATH -subj '//CN=$HOST_NAME//O=$HOST_NAME'

cat $CERT_PATH $KEY_PATH > $CERT_WITH_KEY_PATH
```

### Import the pem file to azure keyvault

```bash
az keyvault certificate import --vault-name <Your Azure Key Vault> -n <cert_name> -f $CERT_WITH_KEY_PATH
```

### Create secret provider class

> **_NOTE:_** Please substitute the necessary placeholder values before running the `secretproviderclass.yaml` and `pod.yaml` files.

```bash
kubectl apply -f secretproviderclass.yaml

kubectl apply -f pod.yaml
```

### Validation 

The ingress, container pod should be successfully running with the volume mount and volume.

```bash
kubectl get pods -n <namespace>
```

![alt text](pods.png)

```bash
kubectl describe pod <pod_name> -n <namespace>
```

![alt text](pod.png)

