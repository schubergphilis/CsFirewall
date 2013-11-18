# Author:: Frank Breedijk <fbreedijk@schubergphilis.com>
# Copyright:: Copyright (c) 2013
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Cookbook Name:: CsFirewall
# Recipe:: default

# This recipe is run by those nodes that manage the couldstack firewall rules

Chef::Log.info("Start of CsFirewall::iptables recipe")

# Lets get the current state of the firewall
ipt = `iptables -L`
rules = Hash.new()
chain = ""
ipt.split("\n").each do |l|
  if ( l =~ /^Chain (.*?) \(policy (.*?)\)/ ) then
    Chef::Log.info("Found chain #{$1} with policy #{$2}")
    chain = $1
    rules[chain] = Hash.new()
    rules[chain]["policy"] = $2
  elsif ( l =~ /^\s*$/ ) then
    Chef::Log.info("Ignoring blank line: #{l}")
  elsif ( l =~ /^target\s+prot/ ) then
    Chef::Log.info("Ignoring header line: #{l}")
  elsif ( l =~ /^\S+\s+\S+\s+\S+\s+\S=\s+\S+/ ) then
    Chef::Log.info("Policy line: #{l}")
  else
    Chef::Log.fatal("Unrecognized line: #{l}")
  end #if
end #split

if ( node['cloudstack'] && node['cloudstack']['firewall'] && node['cloudstack']['firewall']['ingress'] ) then
  # We have inbound firewall rules
  node['cloudstack']['firewall']['ingress'].each do |set,rules|
    Chef::Log.info("Processing inbound ruleset: #{set}")
    rules.each do |rule|
      
    end #rule
  end #set
end # firewall ingress

Chef::Log.info("End of CsFirewall::iptables recipe")
