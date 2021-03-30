#cloud-config

runcmd:
 - sleep 60
 - docker run -p 9100:9100 quay.io/prometheus/node-exporter:latest