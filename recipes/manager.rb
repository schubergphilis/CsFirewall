#
# Cookbook Name:: CsFirewall
# Recipe:: manager
#
# Copyright 2013, Schuberg Philis
#
# All rights reserved - Do Not Redistribute
#

# This recipe is run by those nodes that manage the couldstack firewall

Chef::Log.info("Start of CsFirewall::manager recipe")

gem_package "cloudstack_helper" do
  action :install
end

require 'rubygems'
require 'cloudstack_helper'
require 'json'

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
csapi = CloudStackHelper.new(:api_url => node['cloudstack']['url'],:api_key => node['cloudstack']['APIkey'],:secret_key => node['cloudstack']['SECkey'])

params = { 
  :command => "listPortForwardingRules",
  :response => 'json'
}
json =csapi.get(params).body
pfrules = JSON.parse(json)["listportforwardingrulesresponse"]["portforwardingrule"]

params = { 
  :command => "listFirewallRules",
  :response => 'json'
}
json =csapi.get(params).body
fwrules = JSON.parse(json)["listfirewallrulesresponse"]["firewallrule"]

params = { 
  :command => "listPublicIpAddresses",
  :response => 'json'
}
json =csapi.get(params).body
ips = Hash.new
JSON.parse(json)["listpublicipaddressesresponse"]["publicipaddress"].each do |ip|
  ips[ip["ipaddress"]] = ip["id"]
end

params = { 
  :command => "listVirtualMachines",
  :response => 'json'
}
json =csapi.get(params).body
machines = Hash.new
JSON.parse(json)["listvirtualmachinesresponse"]["virtualmachine"].each do |m|
  machines[m["name"]] = m["id"]
end

# This should probably be a partial search, but I don't get the documentation 
# for that feature
nodes = search(:node, "cloudstack_firewall_ingress:*")

fw_work = false
pf_work = false
# Firewall rules go first
nodes.each do |n|
  unmanaged = n["cloudstack"]["firewall"]["unmanaged"]
  if ( unmanaged != "true" ) then
    Chef::Log.info("Found ingress firewall rules for host: #{n.name}")
    fw_work = true
    # Get all ingress rules
    n["cloudstack"]["firewall"]["ingress"].each do |fw|
      found = false
      # Check for a firewall rule
      fwrules.each do |fwrule|
        #Chef::Log.info(fwrule)
        if ( ( not found ) &&
          fw[0] == fwrule["ipaddress"] &&
          fw[1] == fwrule["protocol"] &&
          fw[2] == fwrule["cidrlist"] &&
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
          :cidrlist => fw[2],
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
              #fw[2] == pfrule["cidrlist"] && 
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
            :cidrlist => fw[2],
            :publicport => fw[3],
            :publicendport => fw[4],
            :privateport => fw[5],
            :privateendport => (fw[5].to_i + fw[4].to_i - fw[3].to_i).to_s,
            :action => "create"
          }
          Chef::Log.info("Port forward rule will be created")
        end
      end #pf rule
    end #ingress
  end # unmanage
end #node

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
        :response => 'json',
        :cidrlist => fwrule[:cidrlist],
        :ipaddressid => ips[fwrule[:ipaddress]],
        :protocol => fwrule[:protocol],
        :startport => fwrule[:startport],
        :endport => fwrule[:endport]
      }
      json =csapi.get(params).body
      jobs.push JSON.parse(json)["createfirewallruleresponse"]["jobid"]
    elsif ( fwrule["action"] == "keep" ) then
      # Do nothing
      Chef::Log.info("Keeping firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]}")
    elsif node["cloudstack"]["firewall"]["cleanup"] == true then
      Chef::Log.info("Deleting firewall rule: #{fwrule["cidrlist"]} -> #{fwrule["ipaddress"]}:#{fwrule["protocol"]} #{fwrule["startport"]}-#{fwrule["endport"]} (id: #{fwrule["id"]})")
      params = {
        :command => "deleteFirewallRule",
        :response => 'json',
        :id => fwrule["id"]
      }
      json =csapi.get(params).body
      jobs.push JSON.parse(json)["deletefirewallruleresponse"]["jobid"]
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
        :response => 'json',
        :protocol => pfrule[:protocol],
        :ipaddressid => ips[pfrule[:ipaddress]],
        :publicport => pfrule[:publicport],
        :publicendport => pfrule[:publicendport],
        :virtualmachineid => machines[pfrule[:virtualmachinename]],
        :privateport => pfrule[:privateport],
        :privateendport => pfrule[:privateendport]
      }
      json =csapi.get(params).body
      jobs.push JSON.parse(json)["createportforwardingruleresponse"]["jobid"]
    elsif ( pfrule["action"] == "keep" ) then
      # Do nothing
      Chef::Log.info("Keeping port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]}")
    elsif node["cloudstack"]["firewall"]["cleanup"] == true then
      Chef::Log.info("Deleting port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]} (d: #{pfrule["id"]})")
      params = {
        :command => "deletePortForwardingRule",
        :response => 'json',
        :id => pfrule["id"]
      }
      json =csapi.get(params).body
      jobs.push JSON.parse(json)["deleteportforwardingruleresponse"]["jobid"]
    else 
      Chef::Log.info("NOT deleting port forward rule: #{pfrule["protocol"]} #{pfrule["ipaddress"]}:#{pfrule["publicport"]}-#{pfrule["publicendport"]} -> #{pfrule["virtualmachinename"]}:#{pfrule["privateport"]}-#{pfrule["privateendport"]} (cleanup disabled)")
    end
  end #pfrule
end

# Wait for all jobs to finish
jobs.each do |job|
  status = 1
  params = {
    :command => "queryAsyncJobResult",
    :response => "json",
    :jobid => job
  }
  json =csapi.get(params).body
  status = JSON.parse(json)["queryasyncjobresultresponse"]["jobstatus"]
  while ( status != 0 ) do
    sleep 1
    json =csapi.get(params).body
    status = JSON.parse(json)["queryasyncjobresultresponse"]["jobstatus"]
  end
  Chef::Log.info("Job #{job} done, status code #{JSON.parse(json)["queryasyncjobresultresponse"]["jobresultcode"]}")
end #jobs

Chef::Log.info("End of CsFirewall::manager recipe")
