#
# Cookbook Name:: CsFirewall
# Recipe:: manager
#
# Copyright 2013, Schuberg Philis
#
# All rights reserved - Do Not Redistribute
#

# This recipe is run by those nodes that manage the couldstack firewall
# de['cloudstack']['

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

# This should probably be a partial search, but I don't get the documentation 
# for that feature
nodes = search(:node, "cloudstack_firewall:*")

nodes.each do |n|
  Chef::Log.info("Found firewall configuration for host: #{n.name}")
  # Get all ingress rules
  n["cloudstack"]["firewall"]["ingress"].each do |fw|
    found = false
    fwrules.each do |r|
      if ( ( not found ) &&
        fw[0] == r["ipaddress"] &&
        fw[1] == r["protocol"] &&
        fw[2] == r["cidrlist"] &&
        fw[3] == r["startport"] &&
        fw[4] == r["endport"] 
      ) then
        r["action"] = "keep"
        found = true
        Chef::Log.info("Match: #{r}")
      else
        Chef::Log.info("No match: #{fw[0]} - #{r["ipaddress"]} - #{r}")
      end
    end
  end
end

Chef::Log.info(fwrules)
