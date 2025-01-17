#!/bin/sh
set -e # dont use -x, as it will leak credentials

# This is not a unit test, as it requires access to docker hub, as well as docker/podman

# first setup podman
cat > /etc/containers/containers.conf <<EOF
[containers]
netns="host"
userns="host"
ipcns="host"
utsns="host"
cgroupns="host"
cgroups="disabled"
log_driver = "k8s-file"
[engine]
cgroup_manager = "cgroupfs"
events_logger="file"
runtime="crun"
EOF

chmod 644 /etc/containers/containers.conf
sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' -e 's|^mountopt[[:space:]]*=.*$|mountopt = "nodev,fsync=0"|g' /etc/containers/storage.conf

mkdir -p /var/lib/shared/overlay-images
touch /var/lib/shared/overlay-images/images.lock

mkdir -p /var/lib/shared/overlay-layers
touch /var/lib/shared/overlay-layers/layers.lock

mkdir -p /var/lib/shared/vfs-images
touch /var/lib/shared/vfs-images/images.lock

mkdir -p /var/lib/shared/vfs-layers
touch /var/lib/shared/vfs-layers/layers.lock

sed -i 's/\/var\/lib\/containers\/storage/$EARTHLY_DOCKERD_DATA_ROOT/g' /etc/containers/storage.conf

if [ -n "$DOCKERHUB_MIRROR" ]; then
    INSECURE=$(if [ "$DOCKERHUB_MIRROR_HTTP" = "true" ] || [ "$DOCKERHUB_MIRROR_INSECURE" = "true" ]; then echo 'true'; else echo 'false'; fi)
    echo "
[[registry]]
prefix=\"docker.io\"
insecure=$INSECURE
location=\"$DOCKERHUB_MIRROR\"
" > /etc/containers/registries.conf
fi

# then do a docker login (if applicable)
if [ "$DOCKERHUB_AUTH" = "true" ]
then
  (test -n "$USERNAME" || (echo "ERROR: USERNAME not set"; exit 1))
  (test -n "$TOKEN" || (echo "ERROR: TOKEN not set"; exit 1))
  if [ -n "$DOCKERHUB_MIRROR" ]
  then
    docker login "$DOCKERHUB_MIRROR" --username="$USERNAME" --password="$TOKEN"
    podman login "$DOCKERHUB_MIRROR" --username="$USERNAME" --password="$TOKEN"
  else
    docker login --username="$USERNAME" --password="$TOKEN"
    podman login --username="$USERNAME" --password="$TOKEN"
  fi
fi

# then run the test
if [ -n "$testname" ]
then
    testarg="-run $testname"
fi
go test -timeout 20m $testarg $pkgname
