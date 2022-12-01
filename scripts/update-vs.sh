#!/bin/bash

# Get console URL, then use that to create virtual service "host"
VSHOST=$(oc whoami --show-console)
VSHOST=${VSHOST/console-openshift-console/frontend}
VSHOST=${VSHOST#"https://"}

echo "Virtual service host: $VSHOST"

pwd

sed -i 's/MYHOST/'$VSHOST'/' manifests/gateway-virtualservice.yaml
sed -i 's/MYHOST/'$VSHOST'/' manifests/gateway-with-tls.yaml