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
#csapi = CloudstackRubyClient::Client.new(node['cloudstack']['url'],node['cloudstack']['APIkey'],node['cloudstack']['SECkey'])
csapi = CloudStackHelper.new(:api_url => node['cloudstack']['url'],:api_key => node['cloudstack']['APIkey'],:secret_key => node['cloudstack']['SECkey'])
#pfrules = csapi.list_network_offerings()
#fwrules = csapi.list_firewall_rules()

params = { 
  :command => "listPortForwardingRules",
  :response => 'json'
}
json =csapi.get(params).body
pfrules = JSON.parse(json)
Chef::Log.info(pfrules)

params = { 
  :command => "listFirewallRules",
  :response => 'json'
}
json =csapi.get(params).body
fwrules = JSON.parse(json)
Chef::Log.info(fwrules)
# This should probably be a partial search, but I don't get the documentation 
# for that feature
nodes = search(:node, "cloudstack_firewall:*")

nodes.each do |n|
  Chef::Log.info("Found firewall configuration for host: #{n.name}")
end

