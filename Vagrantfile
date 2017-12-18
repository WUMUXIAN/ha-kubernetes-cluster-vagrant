# -*- mode: ruby -*-
# # vi: set ft=ruby :

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

$master_vm_memory = 2048
$master_ip_start = "172.17.4.10"

BOX_VERSION = ENV["BOX_VERSION"] || "1465.3.0"
MASTER_COUNT = ENV["MASTER_COUNT"] || 1

Vagrant.configure("2") do |config|
  # always use Vagrant's insecure key
  config.ssh.insert_key = false

  config.vm.box = "container-linux-v${BOX_VERSION}"
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

  # Create the master nodes.
  (1..MASTER_COUNT).each do |m|
    # Set the host name and ip
    master_name = "master-0#{m}"
    master_ip = $master_ip_start + "#{m}"

    config.vm.define master_name do |master|
      master.vm.hostname = master_name
      master.vm.provider :virtualbox do |vb|
        vb.memory = $master_vm_memory
        master.ignition.enabled = true
        vb.customize ["modifyvm", :id, "--natdnspassdomain1", "on"]
        vb.customize ["setextradata", :id, "VBoxInternal/Devices/virtio-net/0/LUN#0/Config/HostResolverMappings/#{master_name}/HostIP", "#{master_ip}"]
        vb.customize ["setextradata", :id, "VBoxInternal/Devices/virtio-net/0/LUN#0/Config/HostResolverMappings/#{master_name}/HostName", "#{master_name}.tdskubes.com"]
      end

      # Set the private ip.
      master.vm.network :private_network, ip: master_ip
      master.ignition.ip = master_ip

      # Set the ignition data.
      master.vm.provider :virtualbox do |vb|
        master.ignition.hostname = "#{master_name}.tdskubes.com"
        master.ignition.drive_root = "provisioning"
        master.ignition.drive_name = "config-master-#{m}"
      end
      masters << master_name
      master_hostvars = {
        master_name => {
          "ansible_port" => 22,
          "ansible_ssh_host" => master_ip,
          "private_ipv4" => master_ip,
          "public_ipv4" => master_ip,
          "role" => "master"
        }
      }
      hostvars.merge!(master_hostvars)
    end
  end

  # Provision
  config.vm.provision :ansible do |ansible|
    ansible.groups = {
      "role=master": masters,
    }
    ansible.host_vars = hostvars
    ansible.playbook = "provisioning/playbook.yml"
  end
end

