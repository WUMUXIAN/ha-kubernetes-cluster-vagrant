#!/bin/bash

openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.crt -subj "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca"