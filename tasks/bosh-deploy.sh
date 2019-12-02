#!/bin/bash -e

. 1-click/tasks/bosh-login.sh

bosh2 upload-stemcell $(cat stemcell/source)
MANIFEST_DEFAULT_STEMCELL=$(bosh interpolate state/environments/softlayer/director/$BOSH_LITE_NAME/cf-deployment/manifest.yml --path=/stemcells/alias=default/version)
bosh2 upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-xenial-go_agent?v=$MANIFEST_DEFAULT_STEMCELL
bosh2 -n -d cf deploy state/environments/softlayer/director/$BOSH_LITE_NAME/cf-deployment/manifest.yml