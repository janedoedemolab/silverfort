#!/bin/bash

default_user="silverfort"
if [ -d "/home/$default_user" ]; then
    user="$default_user"
else
    if [ $SUDO_USER -eq "sfuser"]; then
      echo "This process can't be run by sfuser."
      exit
    fi
    user="$SUDO_USER"
fi

HOMEDIR="/home/$user"

if (( $EUID != 0 )); then
    echo "Please run as root."
    echo "sudo ./renew_k8s_certificates.sh"
    exit
fi

exec > >(tee -i /mnt/silverfort/persistent/installation_logs/certs_renewal.out)
exec 2>&1

echo "================================================="
echo "Backup existing certificates"
echo "-------------------------------------------------"
# Backup certs
mkdir -p /tmp/k8scluster-old-certs/pki
cp -p /etc/kubernetes/pki/*.* /tmp/k8scluster-old-certs/pki

#Backup configs
cp -p /etc/kubernetes/*.conf /tmp/k8scluster-old-certs

#Backup local config
mkdir -p /tmp/k8scluster-old-certs/.kube
cp -p $HOMEDIR/.kube/config /tmp/k8scluster-old-certs/.kube
echo "Backup done."
echo -e "=================================================\n\n"

echo "================================================="
echo "Reading certificate expiration dates"
echo "-------------------------------------------------"
kubeadm certs check-expiration
echo -e "=================================================\n\n"

echo "================================================="
echo "Renewing certificates"
echo "-------------------------------------------------"
kubeadm certs renew all
if [ $? -eq 0 ] ; then
  echo -e "\n\nKubernetes API certificates renewed successfully!"
else
  echo -e "\n\nRenewing kubernetes API certificates failed. Please check the log file:"
  echo "/mnt/silverfort/persistent/installation_logs/certs_renewal.out"
  exit
fi
echo -e "==================================================\n\n"

echo "================================================="
echo "Replacing certificate content"
echo "-------------------------------------------------"
sudo sed -i '/client\-certificate/d' /etc/kubernetes/kubelet.conf
sudo sed -i '/client\-key/d' /etc/kubernetes/kubelet.conf
sudo cat /etc/kubernetes/admin.conf | grep client | sudo tee -a /etc/kubernetes/kubelet.conf
cat /etc/kubernetes/admin.conf | tee $HOMEDIR/.kube/config
if [ $? -eq 0 ] ; then
  echo -e "\n\nCertificate content updated successfully!"
else
  echo -e "\n\nUpdating certificate content failed. Please check the log file:"
  echo "/mnt/silverfort/persistent/installation_logs/certs_renewal.out"
  exit
fi
echo -e "==================================================\n\n"

echo "================================================="
echo "Reading new certificate expiration dates"
echo "-------------------------------------------------"
kubeadm certs check-expiration
echo -e "=================================================\n\n"

echo "================================================="
echo "Restarting system pods"
echo "-------------------------------------------------"
cat <<- 'EOF' > /tmp/podhandler.sh
pods=("kube-apiserver" "kube-controller-manager" "kube-scheduler" "etcd")
for pod in ${pods[@]}; do
  name=$(kubectl get pods -n kube-system | grep $pod | awk '{print $1}')
  kubectl delete pod/$name -n kube-system
done
EOF
chmod o+x /tmp/podhandler.sh
su $user -c /tmp/podhandler.sh
echo -e "=================================================\n\n"

echo "================================================="
echo "Certificate renewal is done."
echo "-------------------------------------------------"
echo "Cleaning workspace..."
rm /tmp/podhandler.sh
rm -r /tmp/k8scluster-old-certs/
echo "Log file located at: /mnt/silverfort/persistent/installation_logs/certs_renewal.out"
echo -e "=================================================\n\n"
