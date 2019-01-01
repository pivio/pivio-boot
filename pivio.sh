#!/bin/sh

OS=$(uname)
HOSTNAME=$(hostname)


# Check if everything we need is there.

if [ "$OS" != "Linux" ] && [ "$OS" != "Darwin" ]; then
  echo Error: Only Linux or MacOS are supported.
  exit 1;
fi

if ! type "docker" > /dev/null; then
  echo Error: You need to have docker installed.
  exit 1;
fi

if ! type "docker-compose" > /dev/null; then
  echo Error: You need to have docker-compose installed.
  exit 1;
fi

if ! type "java" > /dev/null; then
  echo Error: You need to have java installed.
  exit 1;
fi

if ! type "curl" > /dev/null; then
  echo Error: You need to have curl installed.
  exit 1;
fi

if [ "$OS" = "Darwin" ]; then

   NATIVE_DOCKER_CMD=$(docker ps)
   NATIVE_DOCKER=$(echo $?)

  if [ "$NATIVE_DOCKER" -ne 0 ]; then
    echo Check if docker-machine is running.

    if ! type "docker-machine" > /dev/null; then
      echo Error: You need to have docker-machine installed.
      exit 1;
    fi

    DEFAULT_DOCKER_MACHINE=$(docker-machine ls | grep default | grep -c Running)
    if [ "$DEFAULT_DOCKER_MACHINE" -eq 1 ]; then
      HOSTNAME=$(docker-machine ip default)
    else
      echo "Error: a docker-machine with the name 'default' must be running."
      exit 1;
    fi

  else
    echo ==================================================
    printf "You seem like to run docker mac beta. \n PLEASE MAKE SURE YOU HAVE ENABLED THE "
    printf "\n\n EXPERIMENTAL VPN COMPATIBILITY MODE in the settings. \n\n\n"
    printf "\n Press >ENTER< to continue \n"
    echo ==================================================
    read -r
  fi
fi

# Start cloning the repositories.

repos="pivio-web pivio-server pivio-client"

for repo in ${repos}
do
   echo "$repo"
   if [ -d "$repo" ]
   then
      cd "$repo" || exit
      git pull
      cd ..
   else
      git clone https://github.com/pivio/"$repo".git
   fi

   if [[ $repo = pivio-server ]]; then
      cd "$repo" || exit
      git fetch origin spring-boot-1.5.10-to-2.1.1-upgrade
      git checkout spring-boot-1.5.10-to-2.1.1-upgrade
      cd ..
   fi

   cd "$repo" || exit
   if [ -e "build.gradle" ]; then
      ./gradlew build --no-daemon
   fi
   cd ..
done

# Create the docker-compose file.

rm -r docker-compose.yml > /dev/null
cat <<EOF > docker-compose.yml
version: '3'
services:
  pivio-web:
    build: pivio-web/
    ports:
      - "8080:8080"
    environment:
      - PIVIO_SERVER=http://pivio-server:9123
      - PIVIO_SERVER_JS=http://$HOSTNAME:9123
      - PIVIO_VIEW=http://$HOSTNAME:8080
    volumes:
      - $PWD/pivio-conf/:/pivio-conf
    devices:
      - "/dev/urandom:/dev/random"
  pivio-server:
    build: pivio-server/
    ports:
      - "9123:9123"
    devices:
      - "/dev/urandom:/dev/random"
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:6.4.3
    environment:
      - bootstrap.memory_lock=true
      - cluster.name=elasticsearch
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - "xpack.security.enabled=false"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    devices:
      - "/dev/urandom:/dev/random"
EOF

rm -rf pivio-conf
mkdir -p pivio-conf
cat <<EOF > pivio-conf/server_config.yaml
api: http://pivio-server:9123/
js_api: http://$HOSTNAME:9123/
mainurl: http://$HOSTNAME:8080/
pages:
  - description: Overview
    url: /app/overview
    id: tabOverview
  - description: Query
    url: /app/query
    id: tabQuery
  - description: Feed
    url: /app/feed
    id: tabFeed
EOF

docker-compose up -d --build

echo "Waiting for the servers to come up (on $HOSTNAME). This can take a while because of not enough entropy on your machine."

# This can take a while because of missing enough entropy. I you know how
# to speed this up. Let me know. Thanks.

until curl --output /dev/null -X GET --silent --head --fail http://"$HOSTNAME":9123/document; do
    printf '.'
    sleep 5
done

if [ $? -eq 0 ]; then
  echo Waiting for enough entropy for the webserver to be available.
  until curl --output /dev/null -X GET --silent --head --fail http://"$HOSTNAME":8080/; do
      printf '.'
      sleep 5
  done

  echo Open your webbrowser and point it to "$HOSTNAME":8080;
  if [ "$OS" = "Darwin" ]; then
    open http://"$HOSTNAME":8080
  fi
else
  echo "Error: Oops, something went wrong. I'm sorry. Please file a bug report."
  exit 1;
fi

echo "You can stop the demo with 'docker-compose stop'."
