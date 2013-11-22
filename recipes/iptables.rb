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

class Chef::Recipe
  include SearchesLib
end

# Lets get the current state of the firewall
ipt = `iptables -L -n`
rules = Hash.new()
chain = ""
ipt.split("\n").each do |l|
  if ( l =~ /^Chain (.*?) \(policy (.*?)\)/ ) then
    Chef::Log.info("Found chain #{$1} with policy #{$2}")
    chain = $1
    rules[chain] = {
      "policy" => $2,
      "rules" => []
    }
  elsif ( l =~ /^\s*$/ ) then
    Chef::Log.info("Ignoring blank line: #{l}")
  elsif ( l =~ /^target\s+prot/ ) then
    Chef::Log.info("Ignoring header line: #{l}")
  elsif ( l =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*?)\s*$/ ) then 
    Chef::Log.info("Policy line: #{l}")
    rules[chain]["rules"].push({
      "target" => $1,
      "proto" => $2,
      "opt" => $3,
      "source" => $4,
      "destination" => $5,
      "other" => $6
    })
  else
    Chef::Log.fatal("Unrecognized line: #{l}")
  end #if
end #split

if ( node['cloudstack'] && node['cloudstack']['firewall'] && node['cloudstack']['firewall']['ingress'] ) then
  # We have inbound firewall rules
  node['cloudstack']['firewall']['ingress'].each do |set,csrules|
    Chef::Log.info("Processing inbound ruleset: #{set}")
    csrules.each do |rule|
      # IP address, protocol, cidrlist, start, end, nat
      # Expand searches
      cidrlist = expand_search(rule[2])
      # Do some transformations
      if ( (rule[1] == "tcp" || rule[1] == "udp") && rule[3] != rule[4] ) then
        # We have a port range
        txtrule = "#{rule[1]} dpts:#{rule[5]}:#{rule[5].to_i+rule[4].to_i-rule[3].to_i}"
      elsif ( (rule[1] == "tcp" || rule[1] == "udp") && rule[3] == rule[4] ) then
        # We have a single port
        txtrule = "#{rule[1]} dpt:#{rule[5]}"
      else
        Chef::Log.fatal("Cannot translate #{rule.join("\\")} into an iptables rule")
      end
      # expand cidrlist
      cidrlist.split(",").each do |cidr|
        cidr.gsub!(/\/32/,"")
        found = false
        # Find matching iptable rule
        if ( rules["INPUT"] == nil ) then
          Chef::Log.fatal("txtNo INPUT chain found")
        end
        rules["INPUT"]["rules"].each do |iptrule|
          if ( (not found) && 
               iptrule["target"] == "ACCEPT" &&
               iptrule["proto"] == rule[1] &&
               iptrule["source"] == cidr &&
               iptrule["destination"] == "#{node["ipaddress"]}" &&
               iptrule["other"] == txtrule
             ) then
            found = true
            iptrule["action"] = "keep"
          end
        end #iptrule
        if ( not found ) then
          # rule not found, need to create one
          rules["INPUT"]["rules"].push({
            "target" => "ACCEPT",
            "proto" => rule[1],
            "start" => rule[5],
            "end" => (rule[5].to_i()+rule[4].to_i()-rule[3].to_i()).to_s(),
            "destination" => node["ipaddress"],
            "source" => cidr,
            "other" => txtrule,
            "action" => "create"
          })
        end # new rule
      end #cidr
    end #rule
  end #set
end # firewall ingress

# Next ACL rules
if ( node['cloudstack'] && node['cloudstack']['acl'] ) then
  node['cloudstack']['acl'].each do |tag,acl|
    Chef::Log.info("Processing ACLs with tag #{tag}")
    acl.each do |rule|
      # Network, cidrlist, proto, startport, endport, direction
      # Expand searches
      cidrlist = expand_search(rule[1])
      # Do some transformations
      if ( (rule[2] == "tcp" || rule[2] == "udp") && rule[3] != rule[4] ) then
        # We have a port range
        txtrule = "#{rule[2]} dpts:#{rule[3]}:#{rule[4]}"
      elsif ( (rule[2] == "tcp" || rule[2] == "udp") && rule[3] == rule[4] ) then
        # We have a single port
        txtrule = "#{rule[2]} dpt:#{rule[3]}"
      else
        Chef::Log.fatal("Cannot translate #{rule.join("\\")} into an iptables rule")
      end
      # expand cidrlist
      cidrlist.split(",").each do |cidr|
        cidr.gsub!(/\/32/,"")
        found = false
        if ( rule[5] == "Ingress" ) then
          chain = "INPUT"
        elsif ( rule[5] == "Egress" ) then
          chain = "OUTPUT"
        else
          Chef::Log.fatal("Cannot translate direction #{rule[5]} to an iptables chain, rule: #{rule.join("\\")}")
          chain = nil
        end
        # Find matching iptable rule
        if ( rules[chain] == nil ) then
          Chef::Log.fatal("No #{chain} chain found")
        end
        rules[chain]["rules"].each do |iptrule|
          if ( (not found) && 
               iptrule["target"] == "ACCEPT" &&
               iptrule["proto"] == rule[2] &&
               (
                 ( chain == "INPUT" && iptrule["source"] == cidr && iptrule["destination"] == node["ipaddress"] ) ||
                 ( chain == "OUTPUT" && iptrule["destination"] == cidr && iptrule["source"] == node["ipaddress"] )
               ) &&
               iptrule["other"] == txtrule
             ) then
            found = true
            iptrule["action"] = "keep"
          end
        end #iptrule
        if ( not found ) then
          # rule not found, need to create one
          if ( chain == "INPUT" ) then
            rules[chain]["rules"].push({
              "target" => "ACCEPT",
              "proto" => rule[2],
              "start" => rule[3],
              "end" => rule[4],
              "source" => cidr,
              "destination" => node["ipaddress"],
              "other" => txtrule,
              "action" => "create"
            })
          elsif ( chain == "OUTPUT" ) then
            rules[chain]["rules"].push({
              "target" => "ACCEPT",
              "proto" => rule[2],
              "start" => rule[3],
              "end" => rule[4],
              "source" => node["ipaddress"],
              "destination" => cidr,
              "other" => txtrule,
              "action" => "create"
            })
          else
            Chef::Log.fatal("Unknown chain #{chain}")
          end
        end # new rule
      end #cidr
    end #acl
  end
end

# O.K. now for manipulating the iptables rules
delete = Hash.new()
rules.each do |chain,ruleset|
  Chef::Log.info("Setting iptables rule for chain #{chain}")
  count = 1
  delete[chain] = []
  ruleset["rules"].each do |rule|
    if ( rule["action"] == "keep" ) then
      Chef::Log.info("Keeping #{chain} rule: #{rule["source"]}->#{rule["destination"]} #{rule["other"]} -> #{rule["target"]}")
    elsif ( rule["action"] == "create" ) then
      Chef::Log.info("Creating #{chain} rule: #{rule["source"]}->#{rule["destination"]} #{rule["other"]}")
      if ( rule["start"] == rule["end"] ) then
        # Single port
        output = `iptables -A #{chain} -p #{rule["proto"]} --dport #{rule["start"]} -s #{rule["source"]} -d #{rule["destination"]} -j ACCEPT`
        Chef::Log.info(output)
      else
        # multiport
        output = `iptables -A #{chain} -p #{rule["proto"]} --dport #{rule["start"]}:#{rule["end"]} -s #{rule["source"]} -d #{rule["destination"]} -j ACCEPT`
        Chef::Log.info(output)
      end
    else
      Chef::Log.info("Marked for deletion: #{chain} rule: #{rule["source"]}->#{rule["destination"]} #{rule["other"]} -> #{rule["target"]}")
      delete[chain].push(count)
    end
    count+=1
  end # rule
end #rules

delete.each do |chain,rules|
  rules.reverse_each do |number|
    Chef::Log.info("Deleting rule #{number} from chain #{chain}")
    output = `iptables -D #{chain} #{number}`
    Chef::Log.info(output)
  end #rules
end #delete

Chef::Log.info("End of CsFirewall::iptables recipe")
