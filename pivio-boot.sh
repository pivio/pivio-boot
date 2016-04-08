#!/bin/sh

repos=(pivio-web pivio-server pivio-client pivio-demo-data)

for repo in ${repos[@]}
do
   echo $repo
   if [ -d "$repo" ]
   then
      cd $repo
      git pull
      cd ..
   else
      git clone https://github.com/pivio/$repo.git
   fi

   cd $repo
   gradle build
   cd ..
done


HOSTNAME=`hostname`
rm -r docker-compose.yml > /dev/null
cat <<EOF > docker-compose.yml
pivio-web:
  build: pivio-web/
  ports:
   - "8080:8080"
  links:
   - pivio-server
  environment:
  - PIVIO_SERVER=http://pivio-server:9123
  - PIVIO_SERVER_JS=http://$HOSTNAME:9123
  devices:
  - "/dev/urandom:/dev/random"
pivio-server:
  build: pivio-server/
  ports:
   - "9123:9123"
  links:
   - elasticsearch
  devices:
  - "/dev/urandom:/dev/random"
elasticsearch:
  build: pivio-server/src/docker/elasticsearch
  devices:
  - "/dev/urandom:/dev/random"
EOF

docker-compose up -d --force-recreate

sleep 10

# TODO: need to figure out the ip of your docker-machine when running on e.g. mac
##java -jar pivio-client/build/libs/pivio.jar -yamldir $PWD/pivio-demo-data/
