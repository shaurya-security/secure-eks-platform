apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-secret
  namespace: flask
spec:
  refreshInterval: 1h

  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore

  target:
    name: postgres-secret
    creationPolicy: Owner

  data:
    - secretKey: username
      remoteRef:
        key: ${DB_SECRET_ARN}
        property: username

    - secretKey: password
      remoteRef:
        key: ${DB_SECRET_ARN}
        property: password
