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
oc apply -f manifests/servicemeshcontrolplane.yaml
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
oc apply -f manifests/servicemeshmemberroll.yaml
```

### Deploy the BookInfo Sample App

Now, deploy the "Book Info" sample application.  This app consists of a number of microservices.

```
oc apply -n bookinfo -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.2/samples/bookinfo/platform/kube/bookinfo.yaml
```

We also need to deploy an Istio Ingress Gateway to handle incoming traffic:

```
oc apply -n bookinfo -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.2/samples/bookinfo/networking/bookinfo-gateway.yaml
```