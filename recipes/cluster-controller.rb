#
# Cookbook Name:: eucalyptus
# Recipe:: default
#
#Copyright [2014] [Eucalyptus Systems]
##
##Licensed under the Apache License, Version 2.0 (the "License");
##you may not use this file except in compliance with the License.
##You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
##    Unless required by applicable law or agreed to in writing, software
##    distributed under the License is distributed on an "AS IS" BASIS,
##    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##    See the License for the specific language governing permissions and
##    limitations under the License.
##
#
include_recipe "eucalyptus::default"
## Install binaries for the CC
if node["eucalyptus"]["install-type"] == "packages"
  yum_package "eucalyptus-cc" do
    action :upgrade
    options node['eucalyptus']['yum-options']
    flush_cache [:before]
  end
else
  ## Install CC from source from internal repo if it exists
  execute "export JAVA_HOME='/usr/lib/jvm/java-1.7.0-openjdk.x86_64' && export JAVA='$JAVA_HOME/jre/bin/java' && export EUCALYPTUS='#{node["eucalyptus"]["home-directory"]}' && make && make install" do
    cwd "#{node["eucalyptus"]["source-directory"]}/eucalyptus/"
    only_if "ls #{node["eucalyptus"]["source-directory"]}/eucalyptus/cluster"
    creates "#{node["eucalyptus"]["source-directory"]}/eucalyptus/cluster/generated"
    timeout node["eucalyptus"]["compile-timeout"]
  end
  ## Install CLC from open source repo if it exists
  execute "export JAVA_HOME='/usr/lib/jvm/java-1.7.0-openjdk.x86_64' && export JAVA='$JAVA_HOME/jre/bin/java' && export EUCALYPTUS='#{node["eucalyptus"]["home-directory"]}' && make && make install" do
    cwd "#{node["eucalyptus"]["source-directory"]}/"
    only_if "ls #{node["eucalyptus"]["source-directory"]}/cluster"
    creates "#{node["eucalyptus"]["source-directory"]}/cluster/generated"
    timeout node["eucalyptus"]["compile-timeout"]
  end
  ### Create symlink for eucalyptus-cloud service
  tools_dir = "#{node["eucalyptus"]["source-directory"]}/tools"
  if node['eucalyptus']['source-repo'].end_with?("internal")
    tools_dir = "#{node["eucalyptus"]["source-directory"]}/eucalyptus/tools"
  end

  execute "ln -s #{tools_dir}/eucalyptus-cc /etc/init.d/eucalyptus-cc" do
    creates "/etc/init.d/eucalyptus-cc"
  end

  execute "chmod +x #{tools_dir}/eucalyptus-cc"
end

node["eucalyptus"]["topology"]["clusters"].each do |name, info|
  log "Found Cluster" do
    message "Found cluster #{name} with attributes: #{info}"
    level :info
  end
  if info["cc-1"] == node["ipaddress"]
    node.set["eucalyptus"]["local-cluster-name"] = name
    node.save
  end
end

template "#{node["eucalyptus"]["home-directory"]}/etc/eucalyptus/eucalyptus.conf" do
  source "eucalyptus.conf.erb"
  action :create
end

execute "export EUCALYPTUS='#{node["eucalyptus"]["home-directory"]}' && #{node["eucalyptus"]["home-directory"]}/usr/sbin/euca_conf --setup"

ruby_block "Get cluster keys from CLC" do
  block do
    local_cluster_name = node["eucalyptus"]["local-cluster-name"]
    if not Chef::Config[:solo]
      ### CLC is seperate
      clc_ip = node["eucalyptus"]["topology"]["clc-1"]
      clc  = search(:node, "ipaddress:#{clc_ip}").first
      node.set["eucalyptus"]["cloud-keys"][local_cluster_name] = clc["eucalyptus"]["cloud-keys"][local_cluster_name]
    else
      node.set["eucalyptus"]["topology"]["clusters"][local_cluster_name]["cc-1"] = node["ipaddress"]
      node.set["eucalyptus"]["cloud-keys"][local_cluster_name] = node["eucalyptus"]["cloud-keys"][local_cluster_name]
    end
    node.save
    node["eucalyptus"]["cloud-keys"][local_cluster_name].each do |key_name,data|
     file_name = "#{node["eucalyptus"]["home-directory"]}/var/lib/eucalyptus/keys/#{key_name}"
     if data.is_a?(String)
       File.open(file_name, 'w') do |file|  
         file.puts Base64.decode64(data)
       end 
     end
     require 'fileutils'
     FileUtils.chmod 0700, file_name
     FileUtils.chown 'eucalyptus', 'eucalyptus', file_name
    end
  end
end

service "eucalyptus-cc" do
  action [ :enable, :start ]
  supports :status => true, :start => true, :stop => true, :restart => true
end
