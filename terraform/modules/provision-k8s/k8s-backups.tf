# References:
# https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-9816E07A-466C-451D-A43B-D415B2FAB7D6.html#backup-a-stateful-application-running-on-a-tanzu-kubernetes-cluster-3
# https://ruzickap.github.io/k8s-eks-bottlerocket-fargate/part-11
# https://velero.io/docs/v1.8/backup-reference/#schedule-a-backup
# https://velero.io/docs/v1.8/how-velero-works/#set-a-backup-to-expire

resource "kubernetes_namespace" "velero" {
  metadata {
    annotations = {
      name = "velero"
    }

    name = "velero"
  }
  depends_on = [
    null_resource.cluster-functional
  ]
}

resource "helm_release" "velero" {
  name       = "velero"
  namespace  = kubernetes_namespace.velero.id
  wait       = true
  atomic     = true
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "2.29.4"

  values = [
    <<-EOF
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.2.0
        imagePullPolicy: Always
        volumeMounts:
          - mountPath: /target
            name: plugins
      - name: velero-plugin-for-csi
        image: velero/velero-plugin-for-csi:v0.1.2
        imagePullPolicy: Always
        volumeMounts:
          - mountPath: /target
            name: plugins
    configuration:
      provider: aws
      backupStorageLocation:
        bucket: ${local.backup_bucket_fqdn}
        prefix: velero-backups
        config:
          region: ${local.backup_region}
      volumeSnapshotLocation:
        name: volumes
        config:
          region: ${local.backup_region}
        features: EnableCSI
    credentials:
      useSecret: true
      secretContents:
        cloud: |
          [default]
          aws_access_key_id=${local.backup_access_key_id}
          aws_secret_access_key=${local.backup_secret_access_key}
    deployRestic: true
    EOF
  ]

  dynamic "set" {
    for_each = {
      # Nothing yet
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}
