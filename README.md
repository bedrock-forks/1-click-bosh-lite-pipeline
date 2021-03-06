# 1-click-bosh-lite-pipeline

Okay, so it's not exactly "1 click", but this repository makes it trivial to deploy a BOSH Lite VM in the Cloud and manage it using a Concourse pipeline.

The instructions here can in theory be used for any Cloud Provider, but we'll focus on the IBM Cloud, aka Softlayer, as this is where the yamls in this repository were tested on.

This guide shows 2 ways of deploying BOSH Lite into the cloud:
1. Just a BOSH Lite
2. A BOSH Lite VM in the cloud plus a Concourse management pipeline to conveniently delete, re-create, etc. that environment.

## Prerequisites:

```bash
git clone https://github.com/cloudfoundry/bosh-deployment ~/workspace/bosh-deployment
git clone https://github.com/petergtz/1-click-bosh-lite-pipeline ~/workspace/1-click-bosh-lite-pipeline
```

**Important:** Latest known working version of bosh-deployment:
```
cd ~/workspace/bosh-deployment
git co 80c6c8173978c907d4508bb23aa0f81a3d6068b8
```

**Note:** These instructions assume Xenial as BOSH stemcell. If you want to use a BOSH Lite that uses a Trusty BOSH stemcell, check out the tag `trusty` of this git repository.

## Manually Creating a BOSH Lite without Generating a Concourse Management Pipeline

_Don't run this step, if you want a Concourse pipeline instead to management your BOSH Lite in the Cloud. Skip directly to [the section below](#creating-a-bosh-lite-using-a-concourse-management-pipeline) in that case._

```bash
mkdir -p ~/deployments/bosh-lite-in-sl
cd ~/deployments/bosh-lite-in-sl

sudo bosh create-env --state ./state.json \
    ~/workspace/bosh-deployment/bosh.yml \
    --vars-store=vars.yml \
    -o ~/workspace/bosh-deployment/softlayer/cpi-dynamic.yml \
    -v internal_ip=<PROVIDE> \
    -v sl_vlan_public=<PROVIDE> \
    -v sl_vlan_private=<PROVIDE> \
    -v sl_datacenter=<PROVIDE> \
    -v dummy_network_range=<PROVIDE> \
    -v dummy_network_gateway=<PROVIDE> \
    -v dummy_static_ip=<PROVIDE> \
    -v sl_vm_domain=<PROVIDE> \
    -v sl_vm_name_prefix=<PROVIDE> \
    -v sl_username=<PROVIDE> \
    -v sl_api_key=<PROVIDE> \
    -v director_name=bosh \
    -o ~/workspace/bosh-deployment/bosh-lite.yml \
    -o ~/workspace/bosh-deployment/bosh-lite-runc.yml \
    -o ~/workspace/bosh-deployment/jumpbox-user.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/add-etc-hosts-entry.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/increase-max-speed.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/disable-virtual-delete-vms.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/add-dummy-manual-network.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/use-softlayer-cpi-v35.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/use-localhost-blobstore.yml
```

Where the variables are defined as:
- `internal_ip`: Must be `<sl_vm_name_prefix>.<sl_vm_domain>`
- `sl_vlan_public`, `sl_vlan_private`: The numeric IDs of the VLans as they appear in Softlayer
- `sl_datacenter`: The Softlayer datacenter, e.g. `ams03`.
- `dummy_network_range`: A dummy network range. It's unclear if this must actually exist in the Softlayer account, or if it can be completely arbitrary.
- `dummy_network_gateway`: A dummy network gateway. It's unclear if this must actually be a existing network gateway in the Softlayer account, or if it can be completely arbitrary as long as it is within the network range above.
- `dummy_static_ip`: A dummy static IP address that gets used as a network interface for the BOSH VM created in the Softlayer account. It must be within the network range above, but doesn't have to exist.
- `sl_vm_name_prefix`: An arbitrary prefix for the VM name.
- `sl_vm_domain`: An arbitrary domain for the VM name. The full name of the VM will be `sl_vm_name_prefix.sl_vm_domain`
- `sl_username`,`sl_api_key`: This information can be found on your [Softlayer Profile](https://control.softlayer.com/account/user/profile) under **API Access Information** .

> **What's all this `dummy_` stuff about?** Turns out there is no useful documentation around on how to use `softlayer/cpi-dynamic.yml`. However, as we want this process to be as simple as possible, we want to use in fact a dynamic network, which auto-assigns an available IP to our newly created BOSH VM. Hence, we use `softlayer/cpi-dynamic.yml`. Unfortunately, when there is no manual network in the list of networks in the `bosh` `instance_group` the Softlayer CPI NG will skip adding an entry to `/etc/hosts`. The entry there, however, is the very hostname `bosh` CLI uses to talk to the VM after it was created. So by adding a dummy manual network, we force the CPI to create that entry in `/etc/hosts` and enable successful communication netween `bosh` CLI and BOSH VM.

Now you alias the environment and set up login credentials:

```bash
bosh alias-env my-bosh -e <sl_vm_name_prefix>.<sl_vm_domain> --ca-cert <(bosh int ./vars.yml --path /director_ssl/ca)
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=`bosh int ./vars.yml --path /admin_password`
```

Confirm that it works:
```bash
bosh -e my-bosh env

Using environment '<sl_vm_name_prefix>.<sl_vm_domain>' as '?'

Name: ...
User: admin

Succeeded
```

_That's it! You can now use your BOSH Lite._


## Creating a BOSH Lite using a Concourse Management Pipeline

**Prerequisites:** Make sure you have a running [Concourse](https://concourse.ci) server, the [Fly CLI](https://concourse.ci/fly-cli.html) and the [Spruce CLI](https://github.com/geofffranks/spruce#how-do-i-get-started). Spruce version 1.14.0 is known to work fine. Earlier versions may not work as expected.

### Generating the manifest:
```bash
bosh interpolate ~/workspace/bosh-deployment/bosh.yml \
    -o ~/workspace/bosh-deployment/softlayer/cpi-dynamic.yml \
    -v internal_ip=<PROVIDE> \
    -v sl_vlan_public=<PROVIDE> \
    -v sl_vlan_private=<PROVIDE> \
    -v sl_datacenter=<PROVIDE> \
    -v dummy_network_range=<PROVIDE> \
    -v dummy_network_gateway=<PROVIDE> \
    -v dummy_static_ip=<PROVIDE> \
    -v sl_vm_domain=<PROVIDE> \
    -v sl_vm_name_prefix=<PROVIDE> \
    -v sl_username=<PROVIDE> \
    -v sl_api_key=<PROVIDE> \
    -v director_name=bosh \
    -o ~/workspace/bosh-deployment/bosh-lite.yml \
    -o ~/workspace/bosh-deployment/bosh-lite-runc.yml \
    -o ~/workspace/bosh-deployment/jumpbox-user.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/add-etc-hosts-entry.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/increase-max-speed.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/disable-virtual-delete-vms.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/add-dummy-manual-network.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/use-softlayer-cpi-v35.yml \
    -o ~/workspace/1-click-bosh-lite-pipeline/operations/use-localhost-blobstore.yml \
    > bosh-lite-in-sl.yml
```

Where the variables are defined as [above](#manually-creating-a-bosh-lite-without-generating-a-concourse-management-pipeline).

### Creating the Concourse Pipeline to Manage the BOSH Lite VM

```bash
fly \
  -t my-target \
  set-pipeline \
  -p my-pipeline \
  -c <(spruce --concourse merge ~/workspace/1-click-bosh-lite-pipeline/template.yml ~/workspace/1-click-bosh-lite-pipeline/deploy-and-test-cf.yml) \
  -v bosh-manifest="$(sed -e 's/((/_(_(/g' bosh-lite-in-sl.yml )" \
  -v state_git_repo=<PROVIDE>
  -v github-private-key=<PROVIDE> \
  -v bosh_lite_name=<PROVIDE> \
  -v sl_vm_domain=<PROVIDE>
```

You should replace the variables with proper values:
- `bosh_lite_name`: this must match with `sl_vm_name_prefix` from the manifest generation above.
- `state_git_repo`: a **private** git repository to which you have write access. It will be used to store `state.json`, the `/etc/hosts` entry created by the Softlayer CPI, and `vars.yml` that will contain the secrets. In order for the pipeline to run, it should have at least one commit in `master` and `events` branches. **It must not be publicly readable.**
- `github-private-key`: A private key to access the git repository.

The `sed` command is needed, because otherwise Concourse would try to interpret the `((...))` in the manifest. It's basically "escaping" the manifest. The jobs in the pipeline appropriately unescape it.

_That's it! Go to your pipeline and let it run!_

__Hint:__ Start by unpausing it and kicking off `delete-((bosh_lite_name))`.
