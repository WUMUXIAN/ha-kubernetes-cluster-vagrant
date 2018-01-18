#!/bin/bash
set -e

KUBECTL_URL=https://storage.googleapis.com/kubernetes-release/release/v1.7.0/bin/linux/amd64/kubectl

trap "{ rm -f /tmp/cat.txt; }" EXIT

if [ ! -f /home/core/kubectl ];then
  echo "Downloading kubectl"
  curl -sLO $KUBECTL_URL
  chmod +x kubectl
fi

echo "Kubernetes is starting. As a progress check, the list of running pods"
echo " will be periodically printed."
echo
echo "NOTE: this may take 20 minutes or more depending on Internet throughput."
echo "~1GB of data will be downloaded."

sleep 2

# Wait for tectonic.service to complete
SubState=`systemctl show bootkube --property=SubState | awk '{print substr($0,10)}'`
while [ "$SubState" != "exited" ]; do
    if /home/core/kubectl --kubeconfig=/etc/kubernetes/kubeconfig get pods --all-namespaces &> /tmp/cat.txt; then
        cat /tmp/cat.txt
        echo " "
    fi
    echo "Kubernetes is still starting, sleeping 30 seconds"
    sleep 30s
    SubState=`systemctl show bootkube --property=SubState | awk '{print substr($0,10)}'`
done

/home/core/kubectl --kubeconfig=/etc/kubernetes/kubeconfig get pods --all-namespaces > /tmp/cat.txt
cat /tmp/cat.txt

token=`/home/core/kubectl --kubeconfig=/etc/kubernetes/kubeconfig -n kube-system describe $(/home/core/kubectl --kubeconfig=/etc/kubernetes/kubeconfig -n kube-system get secret -o name | grep 'default-token') | awk '/token:/ {print $2}'`
cat << EOF
Kubernetes has started successfully!

Setup your local kubelet, after your configure it properly and set the context to vagrant, you can login to the dashboard by running

  kubelet proxy

  Dashboard address: http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/

  The login token is:
  $token
EOF
