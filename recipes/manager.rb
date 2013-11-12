#
# Cookbook Name:: CsFirewall
# Recipe:: manager
#
# Copyright 2013, Schuberg Philis
#
# All rights reserved - Do Not Redistribute
#

# This recipe is run by those nodes that manage the couldstack firewall rules

class Chef::Recipe
  include SearchesLib
  include ApiLib
end

Chef::Log.info("Start of CsFirewall::manager recipe")

include_recipe "CsFirewall::prerequisites"

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

# Firewall
Chef::Log.info("Getting firewall rules")
fwrules = csapi_do(csapi,{ :command => "listFirewallRules" })["listfirewallrulesresponse"]["firewallrule"]

# Port forward
Chef::Log.info("Getting port forwarding rules")
pfrules = csapi_do(csapi,{:command => "listPortForwardingRules"})["listportforwardingrulesresponse"]["portforwardingrule"]

# Networks
networks = Hash.new
csapi_do(csapi, { :command => "listNetworks" } )["listnetworksresponse"]["network"].each do |nw|
  networks[nw["name"]]=nw
end

# ACLs
params = { 
  :command => "listNetworkACLs",
}
acls = Hash.new
networks.each do |key, nw|
  Chef::Log.info("Getting ACLs of network #{nw["name"]}")
  params[:networkid] = nw["id"]
  acls[nw["name"]] = csapi_do(csapi,params)["listnetworkaclsresponse"]["networkacl"]
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
  if ( unmanaged != "true" ) then
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
        cidrlist = fw[2]
        while ( cidrlist =~ /\{([^\}]*)\}/ ) do
          expanded = cached_searches[$1]
          if ( expanded == nil ) then
            expanded = search_to_cidrlist($1)
            cached_searches[$1] = expanded
          end
          cidrlist.gsub!(/\{#{$1}\}/, expanded)
        end
        # Check for a firewall rule
        fwrules.each do |fwrule|
          #Chef::Log.info(fwrule)
          if ( ( not found ) &&
            fw[0] == fwrule["ipaddress"] &&
            fw[1] == fwrule["protocol"] &&
            cidrlist == fwrule["cidrlist"] &&
            fw[3] == fwrule["startport"] &&
            fw[4] == fwrule["endport"] 
          ) then
            # If a rule is found it means we get to keep it, unless it is a rule we have to create
            found = true
            if ( fwrule["action"] != "create" ) then
              fwrule["action"] = "keep"
              Chef::Log.info("Firewall rule found, keeping")
            end
          end
        end #fwrules
        if ( not found ) then
          # If we have not found a rule, we have to create one
          fwrules << {
            :ipaddress => fw[0],
            :protocol => fw[1],
            :cidrlist => cidrlist,
            :startport => fw[3],
            :endport => fw[4],
            :action => "create"
          }
          Chef::Log.info("Firewall rule will be created")
        end
        
        # If a destination port is set in the ingress rule, we have to have a port forward rule
        if ( fw[5] != nil && fw[5] != "" ) then
          pf_work = true
          found = false
          pfrules.each do |pfrule|
            if ( (not found ) &&
                n.hostname == pfrule["virtualmachinename"] &&
                fw[0] == pfrule["ipaddress"] && 
                fw[1] == pfrule["protocol"] &&
                fw[3] == pfrule["publicport"] && 
                fw[4] == pfrule["publicendport"] &&
                fw[5] == pfrule["privateport"]
              ) then
              # If a rule if found we keep it unless we have to create it
              found = true
              if ( pfrule["action"] != "create" ) then
                pfrule["action"] = "keep"
                Chef::Log.info("Port forward rule found, keeping")
              end
            end
          end #pfrules
          if ( not found ) then
            # Create a rule if we don't have it
            pfrules << {
              :virtualmachinename => n.hostname,
              :ipaddress => fw[0],
              :protocol => fw[1],
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
    end #tag
  end # unmanage
end #node

# This should probably be a partial search, but I don't get the documentation 
# for that feature
nodes = search(:node, "cloudstack_acl:*")

acl_work = Hash.new
nodes.each do |n|
  unmanaged = false
  if ( n["cloudstack"]["firewall"] != nil ) then
    unmanaged = n["cloudstack"]["firewall"]["unmanaged"]
  end
  if ( unmanaged != "true" ) then
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

        # Expand inferface reference(s) in cidr_block
        cidrblock = aclsoll[1] 
        while ( cidrblock =~ /nic_(\d+)/ ) do
          index = $1.to_i
          cidr = "#{machines[name]["nic"][index]["ipaddress"]}/32"
					Chef::Log.info("#{name}->nic_#{index} expanded to cidr '#{cidr}'.")
          cidrblock.gsub!(/nic_#{index}/,cidr)
        end #cidrblock
        
        # Expand searches in cidrblock
        while ( cidrblock =~ /\{([^\}])\}/ ) do
          expanded = cached_searches[$1]
          if ( expanded == nil ) then
            expanded = search_to_cidrblock($1)
            cached_searches[$1] = expanded
          end
          cidrlist.gsub!(/\{#{$1}\}/, expanded)
        end #cidrblock

        found = false
        # Check for an existing acl
        acls[network].each do |acl|
          if ( ( not found ) &&
            cidrblock == acl["cidrlist"] &&
            aclsoll[2] == acl["protocol"] &&
            ( aclsoll[3] == acl["startport"] || aclsoll[3].to_i == acl["icmptype"] ) &&
            ( aclsoll[4] == acl["endport"]   || aclsoll[4].to_i == acl["icmpcode"] ) &&
            aclsoll[5] == acl["traffictype"]
          ) then
            found = true
            if ( acl["action"] != "create" ) then
              acl["action"] = "keep"
              Chef::Log.info("ACL rule found, keeping")
            end
          end
        end #acls
        if ( not found ) then
          # ACL needs to be created
          Chef::Log.info("ACL rule not found, creating")
          if ( aclsoll[2] == "icmp" ) then
            #Chef::Log.info(aclsoll)
            acls[network] << {
              :networkid => networks[network]["id"],
              :cidrlist => cidrblock,
              :protocol => aclsoll[2],
              :icmptype => aclsoll[3],
              :icmpcode => aclsoll[4],
              :traffictype => aclsoll[5],
              :action => "create"
            }
          else
            acls[network] << {
              :networkid => networks[network]["id"],
              :cidrlist => cidrblock,
              :protocol => aclsoll[2],
              :startport => aclsoll[3],
              :endport => aclsoll[4],
              :traffictype => aclsoll[5],
              :action => "create"
            }
          end
        end #found
      end #aclsoll
    end #tags
  end #unmanaged
end #nodes

jobs = Array.new
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
      job = csapi_do(csapi,params)
      if ( job != nil ) then
        jobs.push job["createfirewallruleresponse"]["jobid"]
      end
    elsif ( fwrule["action"] == "keep" ) then
      # Do nothing
      Chef::Log.info("Keeping firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]}")
    elsif node["cloudstack"]["firewall"]["cleanup"] == true then
      Chef::Log.info("Deleting firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]} (id: #{fwrule["id"]})")
      params = {
        :command => "deleteFirewallRule",
        :id => fwrule["id"]
      }
      jobs.push csapi_do(csapi,params)["deletefirewallruleresponse"]["jobid"]
    else 
      Chef::Log.info("NOT deleting firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]} (cleanup disabled)")
    end
  end #fwrule
end

# Next, lets manage port forward rules
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
      job = csapi_do(csapi,params)
      if ( job != nil ) then
        jobs.push job["createportforwardingruleresponse"]["jobid"]
      end
    elsif ( pfrule["action"] == "keep" ) then
      # Do nothing
      Chef::Log.info("Keeping port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]}")
    elsif node["cloudstack"]["firewall"]["cleanup"] == true then
      Chef::Log.info("Deleting port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]} (d: #{pfrule["id"]})")
      params = {
        :command => "deletePortForwardingRule",
        :id => pfrule["id"]
      }
      jobs.push csapi_do(csapi,params)["deleteportforwardingruleresponse"]["jobid"]
    else 
      Chef::Log.info("NOT deleting port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]} (cleanup disabled)")
    end
  end #pfrule
end

# Next, lets manage acls
acl_work.each do |nwname, work|
  acls[nwname].each do |acl|
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
      jobs = csapi_do(csapi,params)
      if ( job != nil ) then
        jobs.push job["createnetworkaclresponse"]["jobid"]
      end
    elsif ( acl["action"] == "keep" ) then
      # Do nothing
      if ( acl["protocol"] == "icmp" ) then
        Chef::Log.info("Keeping acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["icmptype"]}/#{acl["icmpcode"]} #{acl["traffictype"]}")
      else
        Chef::Log.info("Keeping acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["startport"]}/#{acl["endport"]} #{acl["traffictype"]}")
      end
    elsif node["cloudstack"]["firewall"]["cleanup"] == true then
      if ( acl["protocol"] == "icmp" ) then
        Chef::Log.info("Deleting acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["icmptype"]}/#{acl["icmpcode"]} #{acl["traffictype"]} (id: #{acl["id"]})")
      else
        Chef::Log.info("Deleting acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["startport"]}/#{acl["endport"]} #{acl["traffictype"]} (id: #{acl["id"]})")
      end
      Chef::Log.info("Deleting port forward rule: #{acl["protocol"]} #{acl["ipaddress"]}:#{acl["publicport"]}-#{acl["publicendport"]} -> #{acl["virtualmachinename"]}:#{acl["privateport"]}-#{acl["privateendport"]} (d: #{acl["id"]})")
      params = {
        :command => "deleteNetworkACL",
        :id => acl["id"]
      }
      jobs.push csapi_do(csapi,params)["deletenetworkaclresponse"]["jobid"]
    else 
      if ( acl["protocol"] == "icmp" ) then
        Chef::Log.info("Ignoring acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["icmptype"]}/#{acl["icmpcode"]} #{acl["traffictype"]} (id: #{acl["id"]}, (cleanup disabled)")
      else
        Chef::Log.info("Ignoring acl on network #{nwname}: #{acl["cidrlist"]} #{acl["protocol"]} #{acl["startport"]}/#{acl["endport"]} #{acl["traffictype"]} (id: #{acl["id"]}, (cleanup disabled)")
      end
    end
  end #acl
end #aclwork

# Wait for all jobs to finish
jobs.each do |job|
  status = 1
  params = {
    :command => "queryAsyncJobResult",
    :jobid => job
  }
  status = csapi_do(csapi,params)["queryasyncjobresultresponse"]["jobstatus"]
  while ( status != 0 ) do
    sleep 1
    status = csapi_do(csapi,params)["queryasyncjobresultresponse"]["jobstatus"]
  end
  Chef::Log.info("Job #{job} done, status code #{status}")
end #jobs

Chef::Log.info("End of CsFirewall::manager recipe")
