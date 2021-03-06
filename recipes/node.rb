# Start daemons
include_recipe "kube-hops::default"

master_cluster_ip = private_recipe_ip('kube-hops', 'master')

# Create pki directories
directory node['kube-hops']['pki']['dir'] do
  owner node['kube-hops']['user']
  group node['kube-hops']['group']
  mode "700"
end

# Fetch KubeCA certificate from Hopsworks
kube_hops_certs 'ca' do
  path        node['kube-hops']['pki']['dir']
  action :fetch_cert
  not_if { ::File.exist?("#{node['kube-hops']['pki']['dir']}/ca.crt") }
end

# Create kubelet.conf
kube_hops_conf "kubelet" do
  path        node['kube-hops']['conf_dir']
  subject     "/CN=system:node:#{node['fqdn']}/O=system:nodes"
  master_ip   master_cluster_ip
  not_if      { ::File.exist?("#{node['kube-hops']['conf_dir']}/kubelet.conf") }
end

directory node['kube-hops']['kubelet_dir'] do
  user "root"
  group "root"
  mode "700"
end

template "#{node['kube-hops']['kubelet_dir']}/config.yaml" do
  source "kubelet-config.erb"
  owner node['kube-hops']['user']
  group node['kube-hops']['group']
end

# As we are not using kubeadm to join the node we need to template an env file for the
# kubelet unit
centos_conf = ""
if node['platform_family'].eql?("rhel")
  centos_conf = "--runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
end

template "#{node['kube-hops']['kubelet_dir']}/kubeadm-flags.env" do
  source "kubeadm-flags.erb"
  owner "root"
  group "root"
  mode "644"
  variables ({
    'centos_conf': centos_conf
  })
end

# Join node using the token
# Here we don't use kubeadm join command as it will go through the tls bootstrap prcess and the
# csrsigner controller on the master cannot sign csr as it doesn't have access to the ca key.
# We provide the kubelet configuration with the cert already signed and the kubelet configuration.
service 'kubelet' do
  action :start
end
