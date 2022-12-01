# OpenShift Service Mesh with mTLS

## Source Material

Based on the [OpenShift Docs]

## Install OpenShift Service Mesh Operators

Follow the steps outlined in the docs.  This includes installing:
* OpenShift Elasticsearch Operator
* RedHat OpenShift distributed tracing platform Operator
* Kiali Operator
* OpenShift Service Mesh Operator

Note, these are all default installs of *just the operators* - not actual instances of the operators.

Once all of the above operators have been installed, you can move on to the next part.

## Install OpenShift Service Mesh

**Note:** If you're using an RHPDS cluster, use `oc adm new-project` to avoid the creation of `LimitRange` objects in your namespaces.


### Create the Control Plane Project

OpenShift Service Mesh is multi-tenant, so you can have multiple Service Mesh Control Planes in a single cluster.  As such, it doesn't really matter where you create your first `ServiceMeshControlPlane` object.  For this demo, we will stick with the example in the OpenShift docs and use `istio-system`.

```
# Namespace for the control plane.
oc new-project istio-system

# Also create the bookinfo namespace for the example app.
oc new-project bookinfo
```

Next, create the `ServiceMeshControlPlane`.  The important stanza in this yaml file is the `security` stanza enabling mtls for the data plane.

```
  security:
    dataPlane:
      mtls: true
```

Create the contorl plane:

```
oc apply -f manifests/servicemeshcontrolplane.yaml -n istio-system
```

This will take a few minutes to fully deploy.  When it's done, you should see a number of deployments in the `istio-system` namespace, including Jaeger and Kiali.

### Create a Member Roll

Each namespace that you want to participate in the service mesh needs to be added to a `ServiceMeshMemberRoll`.  We will be using the `bookinfo` example, so we will add that namespace to the member roll.

```
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
spec:
  members:
  - bookinfo
```

Create the member roll:

```
oc apply -f manifests/servicemeshmemberroll.yaml -n istio-system
```

### Deploy the BookInfo Sample App

Now, deploy the "Book Info" sample application.  This app consists of a number of microservices.

```
oc apply -n bookinfo -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.2/samples/bookinfo/platform/kube/bookinfo.yaml -n bookinfo
```

We also need to deploy an Istio Ingress Gateway and a Virtual Service to handle incoming traffic.  However, we need to customize the "host" parameter in the Virtual Service.  You can do this manually, or run the following script.  If you edit the file manuall (`manifests/gateway-virtualservice.yaml`), then replace `MYHOST` with `frontend.apps.<your cluster url>`.

```
./scripts/update-vs.sh
```

Then, apply the yaml.

```
oc apply -f manifests/gateway-virtualservice.yaml -n bookinfo
```

Get the gateway URL to use later:

```
# Find the route with the name staring with bookinfo...
oc get route -n istio-system

# Get the route URL:
export GATEWAY_URL=$(oc -n istio-system get route <route name> -o jsonpath='{.spec.host}')

# Make sure it worked.
echo $GATEWAY_URL
```

Then create `DestinationRules` that use mTLS:

```
oc apply -n bookinfo -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.2/samples/bookinfo/networking/destination-rule-all-mtls.yaml
```

The distinguishing fact for these DestinationRules is they set the tls mode to "mutual"

```
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

### Test the App: Mesh mTLS, but not Ingress mTLS

Get the product page URL, then open it in a browser:

```
echo "http://$GATEWAY_URL/productpage"
```

If you open Kiali (the route is in the `istio-system` namespace) and go to the "Graph" page you can select the "bookinfo" namespace to see the service graph.  If the page is empty, change the time range (top-right corner) to 5m or greater.

Under the "Display" drop-down, make sure "Security" is checked (2nd from bottom) so that you will see mTLS status of each service call (little locks on the graph edges).

You have now achieved mTLS within the mesh (service to service), but ingress is currently unencrypted to the Istio Ingress Gateway.

### Enable TLS to the Ingress Gateway

To encrypt traffic from our external service (in this case, an API call from our laptop), we first have to generate certificates.  

```
#!/bin/bash
mkdir -p tlscerts
SUBDOMAIN=$(oc whoami --show-console  | awk -F'apps.' '{print $2}')
CN=frontend.apps.$SUBDOMAIN
echo "Create Root CA and Private Key"
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=example.com' \
-keyout tlscerts/example.com.key -out tlscerts/example.com.crt
echo "Create Certificate and Private Key for $CN"
openssl req -out tlscerts/frontend.csr -newkey rsa:2048 -nodes -keyout tlscerts/frontend.key -subj "/CN=${CN}/O=Great Department"
openssl x509 -req -days 365 -CA tlscerts/example.com.crt -CAkey tlscerts/example.com.key -set_serial 0 -in tlscerts/frontend.csr -out tlscerts/frontend.crt
```

Next, you'll need to create a Secret in the `istio-system` namespace where the Istio control plane is:

```
oc create secret generic frontend-credential \
--from-file=tls.key=tlscerts/frontend.key \
--from-file=tls.crt=tlscerts/frontend.crt \
-n istio-system
```

The following updates need to be made to the gateway:

1. `port` stanza needs to be updated to **443** and **https**
2. `tls` stanza is required, including **SIMPLE** mode (not mutual) and a reference the the certificate secret name.

```
oc apply -f manifests/gateway-with-tls.yaml -n bookinfo
```

The URL will now require `https`:

```
echo "https://$GATEWAY_URL/productpage"
```

Since we created these certs, you will get a self signed certificate warning from your browser that you will have to accept before you will see the page.

Nice!  We now have end-to-end encryption from laptop through the mesh!

What if we also want MUTUAL TLS from your service (your machine in this case) through the mesh?

### Mutal TLS Including Ingress

Generate a new client cert:

```
mkdir -p mtlscerts
CN=great-partner.apps.acme.com
echo "Create Root CA and Private Key"
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=Acme Inc./CN=acme.com' \
-keyout mtlscerts/acme.com.key -out mtlscerts/acme.com.crt
echo "Create Certificate and Private Key for $CN"
openssl req -out mtlscerts/great-partner.csr -newkey rsa:2048 -nodes -keyout mtlscerts/great-partner.key -subj "/CN=${CN}/O=Great Department"
openssl x509 -req -days 365 -CA mtlscerts/acme.com.crt -CAkey mtlscerts/acme.com.key -set_serial 0 -in mtlscerts/great-partner.csr -out mtlscerts/great-partner.crt
```

Update the secret with the clients' CA:

```
oc create secret generic frontend-credential \
--from-file=tls.key=mtlscerts/frontend.key \
--from-file=tls.crt=mtlscerts/frontend.crt \
--from-file=ca.crt=mtlscerts/acme.com.crt \
-n istio-system --dry-run=client -o yaml \
| oc replace -n istio-system secret frontend-credential -f -
```