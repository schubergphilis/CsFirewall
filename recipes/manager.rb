# Author:: Frank Breedijk <fbreedijk@schubergphilis.com>
# Author:: Thijs Houtenbos <thoutenbos@schubergphilis.com>
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

Chef::Log.info("Start of CsFirewall::manager recipe")

begin
  require 'cloudstack_helper'
rescue LoadError
  chef_gem 'cloudstack_helper' do
    action :install
    ignore_failure true
  end
end

include_recipe "CsFirewall::prerequisites"

class Chef::Recipe
  include SearchesLib
  include ApiLib
end

if ( not node["cloudstack"]["url"]  ) then
  Chef::Log.fatal('CsFirewall:manage requires that a cloudstack URL is specified')
end

if ( not node["cloudstack"]["APIkey"] ) then
  Chef::Log.fatal('CsFirewall:manage requires that a cloudstack API key is specified')
end

if ( not node["cloudstack"]["SECkey"] ) then
  Chef::Log.fatal('CsFirewall:manage requires that a cloudstack Secret key is specified')
end

# Get rules from cloudstack
csapi = setup_csapi(node['cloudstack']['url'],node['cloudstack']['APIkey'],node['cloudstack']['SECkey'])

# Firewall Ingress
Chef::Log.info("Getting ingress firewall rules")
fwrules = csapi_do(csapi,{ :command => "listFirewallRules" })["listfirewallrulesresponse"]["firewallrule"]

# Port forward
Chef::Log.info("Getting port forwarding rules")
pfrules = csapi_do(csapi,{:command => "listPortForwardingRules"})["listportforwardingrulesresponse"]["portforwardingrule"]

# Networks
networks = Hash.new
csapi_do(csapi, { :command => "listNetworks" } )["listnetworksresponse"]["network"].each do |nw|
  networks[nw["name"]]=nw
end

# Firewall Egress
egressrules = Hash.new()
params = { 
  :command => "listEgressFirewallRules"
}
networks.each do |key, nw|
  Chef::Log.info("Getting egress firewall rules of network #{nw["name"]}")
  params[:networkid] = nw["id"]
  egressrules[nw["name"]]  = csapi_do(csapi,params)["listegressfirewallrulesresponse"]["firewallrule"]
end #networks

# ACLs
params = { 
  :command => "listNetworkACLs",
}
acls = Hash.new
networks.each do |key, nw|
  Chef::Log.info("Getting ACLs of network #{nw["name"]}")
  params[:networkid] = nw["id"]
  acls[nw["name"]] = csapi_do(csapi,params)["listnetworkaclsresponse"]["networkacl"] || []
end #networks

# IPs
ips = Hash.new
csapi_do(csapi,{ :command => "listPublicIpAddresses" })["listpublicipaddressesresponse"]["publicipaddress"].each do |ip|
  ips[ip["ipaddress"]] = ip["id"]
end

# Machines
machines = Hash.new
csapi_do(csapi,{ :command => "listVirtualMachines" })["listvirtualmachinesresponse"]["virtualmachine"].each do |m|
  machines[m["name"].downcase] = m
end

# This should probably be a partial search, but I don't get the documentation 
# for that feature
nodes = search(:node, "cloudstack_firewall_ingress:*")

fw_work = false
pf_work = false
cached_searches = Hash.new()
# Firewall rules go first
nodes.each do |n|
  unmanaged = n["cloudstack"]["firewall"]["unmanaged"]

  # Prevent nodes in cloudstack from breaking chef run
  name1 = n.name.downcase
  name2 = name1.sub(/\..*$/,"")
  if ( machines[name1] == nil && machines[name2] == nil ) then
    unmanaged = true
    Chef::Log.warn("Skipping node #{n.name} because I couldn't find it in cloudstack")
  end
  if ( unmanaged != true && unmanaged != "true" ) then
    Chef::Log.info("Found ingress firewall rules for host: #{n.name}")
    fw_work = true
    # Get all ingress rules
    tags = Hash.new()
    # Prevent old style from failing
    if n["cloudstack"]["firewall"]["ingress"].kind_of?(Array) then
      tags["theOne"] = n["cloudstack"]["firewall"]["ingress"]
    else
        tags = n["cloudstack"]["firewall"]["ingress"]
    end
    tags.each do |tag,ruleset| 
      ruleset.each do |fw|
        found = false
        # Expand search if found
        cidrlist = expand_search(fw[2])
        # Expand protocol
        fw[1].split(/,/).each do |protocol|
          # Check for a firewall rule
          fwrules.each do |fwrule|
            #Chef::Log.info(fwrule)
            if ( ( not found ) &&
              fw[0] == fwrule["ipaddress"] &&
              protocol == fwrule["protocol"] &&
              cidrlist == fwrule["cidrlist"] &&
              fw[3] == fwrule["startport"] &&
              fw[4] == fwrule["endport"] 
            ) then
              # If a rule is found it means we get to keep it, unless it is a rule we have to create
              found = true
              if ( fwrule["action"] != "create" ) then
                fwrule["action"] = "keep"
                fwrule["CsFirewallTag"] = tag
                Chef::Log.info("Firewall rule found, keeping")
              end
            end
          end #fwrules
          if ( not found ) then
            if ( cidrlist =~ /127\.0\.0\.1\/32/ ) then
              Chef::Log.warn("CIDR block contains 127.0.0.1/32, likely cause: failed search, not creating rule")
            else
              # If we have not found a rule, we have to create one
              fwrules << {
                :ipaddress => fw[0],
                :protocol => protocol,
                :cidrlist => cidrlist,
                :startport => fw[3],
                :endport => fw[4],
                :action => "create"
              }
              Chef::Log.info("Firewall rule will be created")
            end # 127.0.0.1
          end # found
          
          # If a destination port is set in the ingress rule, we have to have a port forward rule
          if ( fw[5] != nil && fw[5] != "" && cidrlist !~ /127\.0\.0\.1\/32/ ) then
            pf_work = true
            found = false
            pfrules.each do |pfrule|
              if ( (not found ) &&
                  n.hostname == pfrule["virtualmachinename"] &&
                  fw[0] == pfrule["ipaddress"] && 
                  protocol == pfrule["protocol"] &&
                  fw[3] == pfrule["publicport"] && 
                  fw[4] == pfrule["publicendport"] &&
                  fw[5] == pfrule["privateport"]
              ) then
                # If a rule if found we keep it unless we have to create it
                found = true
                if ( pfrule["action"] != "create" ) then
                  pfrule["action"] = "keep"
                  pfrule["CsFirewallTag"] = tag
                  Chef::Log.info("Port forward rule found, keeping")
                end
              end
            end #pfrules
            if ( not found ) then
              # Create a rule if we don't have it
              pfrules << {
                :virtualmachinename => n.hostname,
                :ipaddress => fw[0],
                :protocol => protocol,
                :publicport => fw[3],
                :publicendport => fw[4],
                :privateport => fw[5],
                :privateendport => (fw[5].to_i + fw[4].to_i - fw[3].to_i).to_s,
                :action => "create"
              }
              Chef::Log.info("Port forward rule will be created")
            end
          end #pf rule
        end #ruleset
      end #protocol
    end #tag
  else
    Chef::Log.warn("Node #{n["hostname"]} unmanaged, skipping")
  end # unmanaged
end #node

# Egress rules
nodes = search(:node, "cloudstack_firewall_egress:*")
egresswork = Hash.new()

nodes.each do |n|
  unmanaged = false
  if ( n["cloudstack"]["firewall"] != nil ) then
    unmanaged = n["cloudstack"]["firewall"]["unmanaged"]
  end
  # Prevent nodes in cloudstack from breaking chef run
  name1 = n.name.downcase
  name2 = name1.sub(/\..*$/,"")
  if ( machines[name1] == nil && machines[name2] == nil ) then
    unmanaged = true
    Chef::Log.warn("Skipping node #{n.name} because I couldn't find it in cloudstack")
  end
  if ( unmanaged != true && unmanaged != "true" ) then
    Chef::Log.info("Found egress rules for host: #{n.name}")
    # Get egress rules from host
    n["cloudstack"]["firewall"]["egress"].each do |tag,ruleset|
      ruleset.each do |rule|
        # Expand interface references to network names
        if ( rule[0] =~ /^nic_(\d+)$/) then
          index = $1.to_i
          name = n.name.downcase
          if ( machines[name] == nil ) then
            name.sub!(/\..*$/,"") # Strip domain
          end
          if ( machines[name] == nil ) then
            Chef::Log.error("Machine #{n.name} or #{name} cannot be found via cloudstack api")
            network = ""
          else
            network = machines[name]["nic"][index]["networkname"]
          end
          Chef::Log.info("#{name}->nic_#{index} expanded to network '#{network}'.")
        else
          network = rule[0]
        end
        egresswork[network] = true

        #Expand seraches in cidrblock
        cidrblock = expand_search(rule[1])
        
        # Expand protocol
        rule[2].split(/,/).each do |protocol|
          # Search for matching egress rule
          found = false
          if ( egressrules[network] ) then
            egressrules[network].each do |erule|
              if ( ( not found ) &&
              	cidrblock == erule["cidrlist"] &&
              	protocol == erule["protocol"] &&
              	( rule[3] == erule["startport"] || rule[3].to_i == erule["icmptype"] ) &&
              	( rule[4] == erule["endport"] || rule[4].to_i == erule["icmpcode"] ) 
              ) then
              	found = true
              	if ( erule["action"] != "create" ) then
                  erule["action"] = "keep"
                  erule["CsFirewallTag"] = tag
                  Chef::Log.info("Egress rule found, keeping")
              	end
              end 
            end #erule
          end #if
          
          if ( not egressrules[network] ) then
            Chef::Log.fatal("Network #{network} is not in the API scope, we will probably fail")
            egressrules[network] = []
            networks[network] = networks[network] || Hash.new
          end
          if ( not found ) then
            if ( cidrblock =~ /127\.0\.0\.1\/32/ ) then
              Chef::Log.warn("CIDRlist contains 127.0.0.1/32, probable cause: failed search, not adding rule")
            else 
              # Need to create egress fule
              Chef::Log.info("Egress rule not found, creating")
              if ( protocol == "icmp" ) then
                egressrules[network] << {
                  "networkid" => networks[network]["id"] || nil,
                  "cidrlist" => cidrblock,
                  "protocol" => protocol,
                  "imcptype" => rule[3],
                  "icmpcode" => rule[4],
                  "action" => "create",
                  "tags" => [
                    {
                      :key => "CsFirewall",
                      :value => tag
                    }
                  ]
                }
              else 
                egressrules[network] << {
                  "networkid" => networks[network]["id"],
                  "cidrlist" => cidrblock,
                  "protocol" => protocol,
                  "startport" => rule[3],
                  "endport" => rule[4],
                  "action" => "create",
                  "tags" => [
                    {
                      :key => "CsFirewall",
                      :value => tag
                    }
                  ]
                }
              end # 127.0.0.1
            end # found
          end # not found
        end #protocol
      end #ruleset
    end # egress
  else
    Chef::Log.warn("Node #{n["hostname"]} unmanaged, skipping")
  end #unmanaged
end #nodes

# This should probably be a partial search, but I don't get the documentation 
# for that feature
nodes = search(:node, "cloudstack_acl:*")

acl_work = Hash.new
nodes.each do |n|
  unmanaged = false
  if ( n["cloudstack"]["firewall"] != nil ) then
    unmanaged = n["cloudstack"]["firewall"]["unmanaged"]
  end
  
  # Prevent nodes in cloudstack from breaking chef run
  name1 = n.name.downcase
  name2 = name1.sub(/\..*$/,"")
  if ( machines[name1] == nil && machines[name2] == nil ) then
    unmanaged = true
    Chef::Log.warn("Skipping node #{n.name} because I couldn't find it in cloudstack")
  end
  
  if ( unmanaged != true && unmanaged != "true" ) then
    Chef::Log.info("Found acls for host: #{n.name}")
    # Get acls from node
    tags = Hash.new()
    # Prevent old style from failing
    if n["cloudstack"]["acl"].kind_of?(Array) then
      tags["theOne"] = n["cloudstack"]["acl"]
    else
      tags = n["cloudstack"]["acl"]
    end
    tags.each do |tag,ruleset|
      ruleset.each do |aclsoll|
        # Expand interface references to network names
        if ( aclsoll[0] =~ /^nic_\d+$/ ) then
          index = aclsoll[0].sub(/^nic_/,"").to_i
          name = n.name.downcase
          if ( machines[name] == nil ) then
            name = name.sub(/\..*$/,"")
            if ( machines[name] == nil ) then
              Chef::Log.error("Machine #{n.name.downcase} or #{name} cannot be found in the CloudStack API")
              abort("Machine #{n.name.downcase} or #{name} cannot be found in the CloudStack API")
            end
          end
          network = machines[name]["nic"][index]["networkname"]
          Chef::Log.info("#{name}->nic_#{index} expanded to network '#{network}'.")
        else
          network = aclsoll[0]
        end
        acl_work[network] = true

        # Expand searches in cidrblock
        cidrblock = expand_search(aclsoll[1])
        
        # Support multi-direction
        aclsoll[5].split(/,/).each do |traffictype|     
          # Support multi-protocol
          aclsoll[2].split(/,/).each do |protocol|	
            found = false
            # Check for an existing acl
            acls[network].each do |acl|
              if ( ( not found ) &&
                  cidrblock == acl["cidrlist"] &&
                  protocol == acl["protocol"] &&
                  ( aclsoll[3] == acl["startport"] || aclsoll[3].to_i == acl["icmptype"] ) &&
                  ( aclsoll[4] == acl["endport"]   || aclsoll[4].to_i == acl["icmpcode"] ) &&
                  traffictype == acl["traffictype"]
                 ) then
                found = true
                if ( acl["action"] != "create" ) then
                  acl["action"] = "keep"
                  acl["CsFirewallTag"] = tag
                  Chef::Log.info("ACL rule found, keeping")
                end
              end
            end #acls
            if ( not found ) then
              if ( cidrblock =~ /127\.0\.0\.1\/32/ ) then
                Chef::Log.warn("CIDRblock contains 127.0.0.1/32, probable cause: failed search. Not adding rule")
              else
                # ACL needs to be created
                Chef::Log.info("ACL rule not found, creating")
                if ( protocol == "icmp" ) then
                  acls[network] << {
                    :networkid => networks[network]["id"],
                    :cidrlist => cidrblock,
                    :protocol => protocol,
                    :icmptype => aclsoll[3],
                    :icmpcode => aclsoll[4],
                    :traffictype => traffictype,
                    :action => "create"
                  }
                else
                  acls[network] << {
                    :networkid => networks[network]["id"],
                    :cidrlist => cidrblock,
                    :protocol => protocol,
                    :startport => aclsoll[3],
                    :endport => aclsoll[4],
                    :traffictype => traffictype,
                    :action => "create"
                  }
                end #icmp
              end #127.0.0.1
            end #found
          end # protocol
        end #traffictype
      end #aclsoll
    end #tags
  else
    Chef::Log.warn("Node #{n["hostname"]} unmanaged, skipping")
  end #unmanaged
end #nodes

jobs = Array.new
trash = Array.new
# Now, lets manage firewall rules
if ( fw_work ) then
  fwrules.each do |fwrule|
    #Chef::Log.info(fwrule)
    if ( fwrule[:action] == "create" ) then
      # Time to create a firewall rule
      Chef::Log.info("Creating firewall rule: #{fwrule[:cidrlist]} -> #{fwrule[:ipaddress]}:#{fwrule[:protocol]} #{fwrule[:startport]}-#{fwrule[:endport]}")
      params = {
        :command => "createFirewallRule",
        :cidrlist => fwrule[:cidrlist],
        :ipaddressid => ips[fwrule[:ipaddress]],
        :protocol => fwrule[:protocol],
        :startport => fwrule[:startport],
        :endport => fwrule[:endport]
      }
      job = csapi_do(csapi,params,false,true)
    elsif ( fwrule["action"] == "keep" ) then
      # Keep firewall rule, but tag
      Chef::Log.info("Keeping firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]}")
    else
      # Tag rule for deletion
      trash.push(fwrule)
    end
  end #fwrule
  clean = false
  actiontext = "NOT deleting"
  if ( node["cloudstack"]["firewall"]["cleanup"] == true ||  node["cloudstack"]["firewall"]["fwcleanup"] == true ) then
    clean = true
    actiontext = "Deleting"
    if ( node['cloudstack']['firewall']['maxdelete'] >= 0 && trash.length > node['cloudstack']['firewall']['maxdelete'] ) then
      Chef::Log.info("Not deleting firewall rules, #{trash.length} marked for deletion, but maxdelete is set to #{node['cloudstack']['firewall']['maxdelete']}")
      abort("CsFirewall run failed. Too many rules would have been deleted. Are you sure you configuration is sane?!?!?!? Disabled cleanup to see which rules would be deleted")
    end
  else
    Chef::Log.info("Not deleting firewall rules, cleanup is disabled")
  end
  trash.each do |fwrule|
    Chef::Log.warn("#{actiontext} firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]} (id: #{fwrule["id"]})")
    if ( clean ) then
      params = {
        :command => "deleteFirewallRule",
        :id => fwrule["id"]
      }
      csapi_do(csapi,params,false,true)
    end
  end #fwrule
end

# Next, lets manage port forward rules
trash = Array.new
if ( pf_work ) then
  pfrules.each do |pfrule|
    #Chef::Log.info(pfrule)
    if ( pfrule[:action] == "create" ) then
      # Time to create a port forward rule
      Chef::Log.info("Creating port forward rule: #{pfrule[:protocol]} #{pfrule[:ipaddress]}:#{pfrule[:publicport]}-#{pfrule[:publicendport]} -> #{pfrule[:virtualmachinename]}:#{pfrule[:privateport]}-#{pfrule[:privateendport]}")
      params = {
        :command => "createPortForwardingRule",
        :protocol => pfrule[:protocol],
        :ipaddressid => ips[pfrule[:ipaddress]],
        :publicport => pfrule[:publicport],
        :publicendport => pfrule[:publicendport],
        :virtualmachineid => machines[pfrule[:virtualmachinename]]["id"],
        :privateport => pfrule[:privateport],
        :privateendport => pfrule[:privateendport]
      }
      csapi_do(csapi,params,false,true)
      #job = csapi_do(csapi,params)
      #if ( job != nil ) then
      #  jobs.push job["createportforwardingruleresponse"]["jobid"]
      #end
    elsif ( pfrule["action"] == "keep" ) then
      # Tag rule
      Chef::Log.info("Keeping port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]}")
    else
      # Tag rule for deletion
      trash.push(pfrule)
    end
  end #pfrule

  clean = false
  actiontext = "NOT deleting"
  if ( node["cloudstack"]["firewall"]["cleanup"] == true || node["cloudstack"]["firewall"]["forwardcleanup"] == true ) then
    clean = true
    actiontext = "Deleting"
    if ( node['cloudstack']['firewall']['maxdelete'] >= 0 && trash.length > node['cloudstack']['firewall']['maxdelete'] ) then
      Chef::Log.info("Not deleting port forwarding rules, #{trash.length} marked for deletion, but maxdelete is set to #{node['cloudstack']['firewall']['maxdelete']}")
      abort("CsFirewall run failed. Too many rules would have been deleted. Are you sure you configuration is sane?!?!?!? Disabled cleanup to see which rules would be deleted")
    end
  else
    Chef::Log.info("Not deleting port forwarding rules, cleanup is disabled")
  end
  trash.each do |pfrule|
    Chef::Log.info("#{actiontext} port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]} (d: #{pfrule["id"]})")
    if ( clean ) then
      params = {
        :command => "deletePortForwardingRule",
        :id => pfrule["id"]
      }
      csapi_do(csapi,params,false,true)
    end
  end #pfrule
end

# Let's manage egress rulles
trash = Array.new
egresswork.each do |nwname, work|
  Chef::Log.info("Managing egress rules for network #{nwname}")
  egressrules[nwname].each do |rule|
    #Chef::Log.info(rule)
    if ( rule["action"] == "create" ) then
      # We need to create a rule
      params = {
        :command => "createEgressFirewallRule",
        :networkid => rule["networkid"],
        :cidrlist => rule["cidrlist"],
        :protocol => rule["protocol"]
      }
      if ( rule["protocol"] == "icmp" ) then
        Chef::Log.info("Creating egress rule on network #{nwname}: 0.0.0.0/0->#{rule["cidrlist"]} #{rule["protocol"]} #{rule["icmptype"]}/#{rule["icmpcode"]}")
        params[:icmptype] = rule["icmptype"]
        params[:icmpcode] = rule["icmpcode"]
      else
        Chef::Log.info("Creating egress rule on network #{nwname}: 0.0.0.0/0->#{rule["cidrlist"]} #{rule["protocol"]} #{rule["startport"]}/#{rule["endport"]}")
        params[:startport] = rule["startport"]
        params[:endport] = rule["endport"]
      end
      csapi_do(csapi,params,false,true)
      #job = csapi_do(csapi,params)
      #if ( job != nil ) then
      #  jobs.push job["createegressfirewallruleresponse"]["jobid"]
      #end
    elsif ( rule["action"] == "keep" ) then
      # We need to keep and tag this rule
      if ( rule["protocol"] == "icmp" ) then
        Chef::Log.info("Keeping egress rule on network #{nwname}: 0.0.0.0/0->#{rule["cidrlist"]} #{rule["protocol"]} #{rule["icmptype"]}/#{rule["icmpcode"]}")
      else
        Chef::Log.info("Keeping egress rule on network #{nwname}: 0.0.0.0/0->#{rule["cidrlist"]} #{rule["protocol"]} #{rule["startport"]}/#{rule["endport"]}")
      end
    else
      # Mark rule for deletion
      trash.push(rule)
    end
  end #egressrules
end #egresswork

clean = false
actiontext = "NOT deleting"
if ( node["cloudstack"]["firewall"]["cleanup"] == true || node["cloudstack"]["firewall"]["egresscleanup"] == true ) then
  clean = true
  actiontext = "Deleting"
  if ( node['cloudstack']['firewall']['maxdelete'] >= 0 && trash.length > node['cloudstack']['firewall']['maxdelete'] ) then
    Chef::Log.info("Not deleting egress rules, #{trash.length} marked for deletion, but maxdelete is set to #{node['cloudstack']['firewall']['maxdelete']}")
    abort("CsFirewall run failed. Too many rules would have been deleted. Are you sure you configuration is sane?!?!?!? Disabled cleanup to see which rules would be deleted")
  end
else
  Chef::Log.info("Not deleting egress rules, cleanup is disabled")
end
trash.each do |rule|
  if ( rule["protocol"] == "icmp" ) then
    Chef::Log.info("#{actiontext} egress rule on network #{nwname}: 0.0.0.0/0->#{rule["cidrlist"]} #{rule["protocol"]} #{rule["icmptype"]}/#{rule["icmpcode"]}")
  else
    Chef::Log.info("#{actiontext} egress rule on network #{nwname}: 0.0.0.0/0->#{rule["cidrlist"]} #{rule["protocol"]} #{rule["startport"]}/#{rule["endport"]}")
  end
  if ( clean ) then
    params = { 
      :command => "deleteEgressFirewallRule",
      :id => rule["id"]
    }
    csapi_do(csapi,params,false,true)
  end
end

# Next, lets manage acls
trash = Array.new
acl_work.each do |nwname, work|
  if ( ( 
        # We don't have a selection of managed or unmanaged ACLs
        node['cloudstack']['firewall']['managedacls'] == nil &&
        node['cloudstack']['firewall']['unmanagedacls'] == nil
       ) || (
        # We have managed acls and our network is on it
        node['cloudstack']['firewall']['managedacls'] && 
        node['cloudstack']['firewall']['managedacls'].include?(nwname) 
       ) || ( 
        # We have unmanaged acls and our network is not on it
        node['cloudstack']['firewall']['unmanagedacls'] && 
        ! node['cloudstack']['firewall']['unmanagedacls'].include?(nwname)
      )
     ) then
      acls[nwname].uniq.each do |acl|
    	#Chef::Log.info(acl)
        if ( acl[:action] == "create" ) then
      	# Time to create an acl
      	if ( acl["protocol"] == "icmp" ) then
          Chef::Log.info("Creating acl on network #{nwname}: #{acl[:cidrlist]} #{acl[:protocol]} #{acl[:icmptype]}/#{acl[:icmpcode]} #{acl[:traffictype]}")
        else
          Chef::Log.info("Creating acl on network #{nwname}: #{acl[:cidrlist]} #{acl[:protocol]} #{acl[:startport]}/#{acl[:endport]} #{acl[:traffictype]}")
      	end
      	params = {
          :command => "createNetworkACL",
          :networkid => acl[:networkid],
          :cidrlist => acl[:cidrlist],
          :protocol => acl[:protocol],
          :traffictype => acl[:traffictype]
      	}
      	if ( acl[:protocol] == "icmp" ) then
          params[:icmptype] = acl[:icmptype]
          params[:icmpcode] = acl[:icmpcode]
      	else
          params[:startport] = acl[:startport]
          params[:endport] = acl[:endport]
      	end
      	csapi_do(csapi,params,false,true)
      elsif ( acl["action"] == "keep" ) then
      	# Do nothing
        if ( acl["protocol"] == "icmp" ) then
          Chef::Log.info("Keeping acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["icmptype"]}/#{acl["icmpcode"]} #{acl["traffictype"]}")
        else
          Chef::Log.info("Keeping acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["startport"]}/#{acl["endport"]} #{acl["traffictype"]}")
        end
      else
        # Mark rule for deletion
        trash.push(acl)
      end
    end # if
  end #acl
end #aclwork

clean = false
actiontext = "NOT deleting"
if ( node["cloudstack"]["firewall"]["cleanup"] == true || node["cloudstack"]["firewall"]["aclcleanup"] == true ) then
  clean = true
  actiontext = "Deleting"
  if ( node['cloudstack']['firewall']['maxdelete'] >= 0 && trash.length > node['cloudstack']['firewall']['maxdelete'] ) then
    Chef::Log.info("Not deleting acl rules, #{trash.length} marked for deletion, but maxdelete is set to #{node['cloudstack']['firewall']['maxdelete']}")
    abort("CsFirewall run failed. Too many rules would have been deleted. Are you sure you configuration is sane?!?!?!? Disabled cleanup to see which rules would be deleted")
  end
else
  Chef::Log.info("Not deleting acl rules, cleanup is disabled")
end
trash.each do |acl|
  if ( acl["protocol"] == "icmp" ) then
    Chef::Log.info("#{actiontext} acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["icmptype"]}/#{acl["icmpcode"]} #{acl["traffictype"]} (id: #{acl["id"]})")
  else
    Chef::Log.info("#{actiontext} acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["startport"]}/#{acl["endport"]} #{acl["traffictype"]} (id: #{acl["id"]})")
  end
  if ( clean ) then
    params = {
      :command => "deleteNetworkACL",
      :id => acl["id"]
    }
    csapi_do(csapi,params,false,true)
  end 
end #trash
	
# Wait for all jobs to finish
jobs.each do |job|
  params = {
    :command => "queryAsyncJobResult",
    :jobid => job
  }
  Chef::Log.info("Checking status of job #{job}")
  status = csapi_do(csapi,params)["queryasyncjobresultresponse"]
  while ( status["jobstatus"] == 0 ) do
    Chef::Log.info("Status of job #{job} is #{status["jobstatus"]}")
    sleep 1
    status = csapi_do(csapi,params)["queryasyncjobresultresponse"]
  end
  Chef::Log.info("Job #{job} done, result: #{job["jobresult"]}.")
end #jobs

Chef::Log.info("End of CsFirewall::manager recipe")
