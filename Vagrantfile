# -*- mode: ruby -*-
# # vi: set ft=ruby :

require 'fileutils'
require 'open-uri'
require 'tempfile'
require 'yaml'
require 'openssl'
require 'base64'
require 'securerandom'

Vagrant.require_version ">= 1.9.7"

# Make sure the vagrant-ignition plugin is installed
required_plugins = %w(vagrant-ignition)

plugins_to_install = required_plugins.select { |plugin| not Vagrant.has_plugin? plugin }
if not plugins_to_install.empty?
  puts "Installing plugins: #{plugins_to_install.join(' ')}"
  if system "vagrant plugin install #{plugins_to_install.join(' ')}"
    exec "vagrant #{ARGV.join(' ')}"
  else
    abort "Installation of one or more plugins has failed. Aborting."
  end
end

$master_vm_memory = 1024
$master_ip_start = "172.17.5.10"

BOX_VERSION = ENV["BOX_VERSION"] || "1465.3.0"
MASTER_COUNT = ENV["MASTER_COUNT"] || 3
IGNITION_PATH = File.expand_path("./provisioning/node.ign")

def signTLS(is_ca:, subject:, issuer_subject:'', issuer_cert:nil, public_key:, ca_private_key:, key_usage:'', extended_key_usage:'', san:'')
  cert = OpenSSL::X509::Certificate.new
  cert.subject = OpenSSL::X509::Name.parse(subject)
  if (is_ca)
    cert.issuer = OpenSSL::X509::Name.parse(subject)
  else
    cert.issuer = OpenSSL::X509::Name.parse(issuer_subject)
  end
  cert.not_before = Time.now
  cert.not_after = Time.now + 365 * 24 * 60 * 60
  cert.public_key = public_key
  cert.serial = Random.rand(1..65534)
  cert.version = 2

  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = cert
  if (is_ca)
    ef.issuer_certificate = cert
  else
    ef.issuer_certificate = issuer_cert
  end
  if (is_ca)
    cert.extensions = [
      ef.create_extension("keyUsage", "digitalSignature,keyEncipherment,keyCertSign", true),
      ef.create_extension("basicConstraints","CA:TRUE", true),
      ef.create_extension("subjectKeyIdentifier", "hash"),
  ]
  else
    # The ordering of these statements is done the way it is to match the way terraform does it
    cert.extensions = []
    if (key_usage != "")
      cert.extensions += [ef.create_extension("keyUsage", key_usage, true)]
    end
    if (extended_key_usage != "")
      cert.extensions += [ef.create_extension("extendedKeyUsage", extended_key_usage, true)]
    end
    cert.extensions += [ef.create_extension("basicConstraints","CA:FALSE", true)]
    cert.extensions += [ef.create_extension("authorityKeyIdentifier", "keyid,issuer")]
    if (san != "")
      cert.extensions += [ef.create_extension("subjectAltName", san, false)]
    end
  end

  cert.sign ca_private_key, OpenSSL::Digest::SHA256.new
  return cert
end

Vagrant.configure("2") do |config|
  # always use Vagrant's insecure key
  config.ssh.insert_key = false

  config.vm.box = "container-linux-v#{BOX_VERSION}"
  config.vm.box_url = "https://beta.release.core-os.net/amd64-usr/#{BOX_VERSION}/coreos_production_vagrant_virtualbox.box"

  config.vm.provider :virtualbox do |v|
    # On VirtualBox, we don't have guest additions or a functional vboxsf
    # in CoreOS, so tell Vagrant that so it can be smarter.
    v.check_guest_additions = false
    v.functional_vboxsf     = false
  end

  # plugin conflict
  if Vagrant.has_plugin?("vagrant-vbguest") then
    config.vbguest.auto_update = false
  end

  config.vm.provider :virtualbox do |vb|
    vb.cpus = 1
    vb.gui = false
  end

  hostvars, masters = {}, []

  if ARGV[0] == 'up'
    FileUtils::mkdir_p 'provisioning/roles/etcd/files'
    FileUtils::mkdir_p 'provisioning/roles/kubelet/files'
    # BEGIN ETCD CA
    etcd_key = OpenSSL::PKey::RSA.new(2048)
    etcd_public_key = etcd_key.public_key

    etcd_cert = signTLS(is_ca:          true,
                        subject:        "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                        public_key:     etcd_public_key,
                        ca_private_key: etcd_key,
                        key_usage:      "digitalSignature,keyEncipherment,keyCertSign")

    etcd_file = File.new("provisioning/roles/etcd/files/ca.crt", "wb")
    etcd_file.syswrite(etcd_cert.to_pem)
    etcd_file.close
    # END ETCD CA

    IPs = []
    (1..MASTER_COUNT).each do |m|
      IPs << "IP:" + $master_ip_start + "#{m}"
    end

    (1..MASTER_COUNT).each do |m|
      # BEGIN ETCD PEER
      peer_key = OpenSSL::PKey::RSA.new(2048)
      peer_public_key = peer_key.public_key

      peer_cert = signTLS(is_ca:              false,
                          subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd",
                          issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                          issuer_cert:        etcd_cert,
                          public_key:         peer_public_key,
                          ca_private_key:     etcd_key,
                          key_usage:          "keyEncipherment",
                          extended_key_usage: "serverAuth,clientAuth",
                          san:                "DNS:localhost,DNS:*.tdskubes.com,DNS:*.kube-etcd.kube-system.svc.cluster.local,DNS:kube-etcd-client.kube-system.svc.cluster.local,#{IPs.join(',')},IP:10.3.0.15,IP:10.3.0.20")

      peer_file = File.new("provisioning/roles/etcd/files/master0#{m}.crt", "wb")
      peer_file.syswrite(peer_cert.to_pem)
      peer_file.close

      peer_key_file= File.new("provisioning/roles/etcd/files/master0#{m}.key", "wb")
      peer_key_file.syswrite(peer_key.to_pem)
      peer_key_file.close
      # END ETCD PEER
    end

    # BEGIN ETCD SERVER
    server_key = OpenSSL::PKey::RSA.new(2048)
    server_public_key = server_key.public_key

    server_cert = signTLS(is_ca:              false,
                          subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd",
                          issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                          issuer_cert:        etcd_cert,
                          public_key:         server_public_key,
                          ca_private_key:     etcd_key,
                          key_usage:          "keyEncipherment",
                          extended_key_usage: "serverAuth",
                          san:                "DNS:localhost,DNS:*.kube-etcd.kube-system.svc.cluster.local,DNS:kube-etcd-client.kube-system.svc.cluster.local,IP:127.0.0.1,#{IPs.join(',')},IP:10.3.0.15,IP:10.3.0.20")

    server_file = File.new("provisioning/roles/etcd/files/server.crt", "wb")
    server_file.syswrite(server_cert.to_pem)
    server_file.close

    server_key_file= File.new("provisioning/roles/etcd/files/server.key", "wb")
    server_key_file.syswrite(server_key.to_pem)
    server_key_file.close
    # END ETCD SERVER

    # BEGIN ETCD CLIENT
    etcd_client_key = OpenSSL::PKey::RSA.new(2048)
    etcd_client_public_key = etcd_client_key.public_key

    etcd_client_cert = signTLS(is_ca:              false,
                               subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd",
                               issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                               issuer_cert:        etcd_cert,
                               public_key:         etcd_client_public_key,
                               ca_private_key:     etcd_key,
                               key_usage:          "keyEncipherment",
                               extended_key_usage: "clientAuth")

    etcd_client_file_tec = File.new("provisioning/roles/etcd/files/etcd-client.crt", "wb")
    etcd_client_file_tec.syswrite(etcd_client_cert.to_pem)
    etcd_client_file_tec.close

    etcd_client_file_tec = File.new("provisioning/roles/etcd/files/etcd-client.key", "wb")
    etcd_client_file_tec.syswrite(etcd_client_key.to_pem)
    etcd_client_file_tec.close
    # END ETCD CLIENT

    # BEGIN KUBE CA
    kube_key = OpenSSL::PKey::RSA.new(2048)
    kube_public_key = kube_key.public_key
    kube_cert = signTLS(is_ca:          true,
                        subject:        "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=kube-ca",
                        public_key:     kube_public_key,
                        ca_private_key: kube_key,
                        key_usage:      "digitalSignature,keyEncipherment,keyCertSign")

    kube_file_tls = File.new("provisioning/roles/kubelet/files/ca.crt", "wb")
    kube_file_tls.syswrite(kube_cert.to_pem)
    kube_file_tls.close
    kube_key_file= File.new("provisioning/roles/kubelet/files/ca.key", "wb")
    kube_key_file.syswrite(kube_key.to_pem)
    kube_key_file.close
    # END KUBE CA

    # BEGIN KUBE CLIENT (KUBELET)
    client_key = OpenSSL::PKey::RSA.new(2048)
    client_public_key = client_key.public_key

    client_cert = signTLS(is_ca:              false,
                          subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=kubelet",
                          issuer_subject:     "/C=/ST=/L=/postalCode=/O=bootkube/OU=/CN=kube-ca",
                          issuer_cert:        kube_cert,
                          public_key:         client_public_key,
                          ca_private_key:     kube_key,
                          key_usage:          "digitalSignature,keyEncipherment",
                          extended_key_usage: "serverAuth,clientAuth")

    client_file_tls = File.new("provisioning/roles/kubelet/files/kubelet.crt", "wb")
    client_file_tls.syswrite(client_cert.to_pem)
    client_file_tls.close
    client_key_file= File.new("provisioning/roles/kubelet/files/kubelet.key", "wb")
    client_key_file.syswrite(client_key.to_pem)
    client_key_file.close
    # END CLIENT

    # START KUBECONFIG
    data = File.read("provisioning/roles/kubelet/templates/kubeconfig.tmpl")
    data = data.gsub("{{CA_CERT}}", Base64.strict_encode64(kube_cert.to_pem))
    data = data.gsub("{{CLIENT_CERT}}", Base64.strict_encode64(client_cert.to_pem))
    data = data.gsub("{{CLIENT_KEY}}", Base64.strict_encode64(client_key.to_pem))

    kubeconfig_file = File.new("provisioning/roles/kubelet/templates/kubeconfig.j2", "wb")
    kubeconfig_file.syswrite(data)
    kubeconfig_file.close
    # END KUBECONFIG
  end

  # Create the master nodes.
  (1..MASTER_COUNT).each do |m|
    # Set the host name and ip
    master_name = "master0#{m}"
    master_ip = $master_ip_start + "#{m}"
    last = (m >= MASTER_COUNT)

    config.vm.define master_name, primary: last do |master|
      master.vm.hostname = master_name
      master.vm.provider :virtualbox do |vb|
        vb.memory = $master_vm_memory
        master.ignition.enabled = true
      end

      # Set the private ip.
      master.vm.network :private_network, ip: master_ip
      master.ignition.ip = master_ip

      # Set the ignition data.
      master.vm.provider :virtualbox do |vb|
        master.ignition.hostname = "#{master_name}.tdskubes.com"
        master.ignition.drive_root = "provisioning"
        master.ignition.drive_name = "config-master-#{m}"
        master.ignition.path = IGNITION_PATH
      end
      masters << master_name
      master_hostvars = {
        master_name => {
          "ansible_python_interpreter" => "/home/core/bin/python",
          "private_ipv4" => master_ip,
          "public_ipv4" => master_ip,
          "role" => "master",
        }
      }
      hostvars.merge!(master_hostvars)

      # Provision only when all machines are up and running.
      if last
        config.vm.provision :ansible do |ansible|
          ansible.groups = {
            "role=master": masters,
            "all": masters,
          }
          ansible.host_vars = hostvars
          # this will force the provision to happen on all machines to achieve parallel provisioning.
          ansible.limit = "all"
          ansible.playbook = "provisioning/playbook.yml"
        end
      end
    end
  end
end
