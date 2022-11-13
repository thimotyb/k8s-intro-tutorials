kubectl create namespace logging
kubectl create deployment elasticsearch --image=docker.elastic.co/elasticsearch/elasticsearch:6.7.0
kubectl expose deployment elasticsearch --port 9200

