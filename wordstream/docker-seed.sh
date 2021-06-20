#!/usr/bin/env bash
#This  seeding script  is to be run on a MiniKube environment ONLY. It will not work in a standard
#Kubernetes cluster
docker run -d -p 5000:5000 --restart=always --name registry registry:2

#Create the wordstream producer container image

docker build -t wordstream-producer . -f Dockerfile_producer

docker tag  wordstream-producer  localhost:5000/wordstream-producer

docker push localhost:5000/wordstream-producer

#Create the wordstream consumer container image

docker build -t wordstream-consumer . -f Dockerfile_consumer

docker tag  wordstream-consumer  localhost:5000/wordstream-consumer

docker push localhost:5000/wordstream-consumer

#List the images in the registry

curl http://localhost:5000/v2/_catalog


