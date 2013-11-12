CsFirewall Cookbook
===================
This cookbook enforces the firewall rules in cloudstack via a firewall 
management node that interacts with the API

Make sure you assign at least one node in the network the CsFirewall::manage 
role if you want to have your rules enforce in cloudstack. These machines are 
the machines that will actually talk to the Clud Stack API via http(s)

Requirements
------------
The cloudstack_helper gem needs to be installed on the firewall management
node(s) to access the API
If you use embeeded Ruby, make sure that you install it in this version

Attributes
----------
TODO: List you cookbook attributes here.

e.g.
#### CsFirewall::default
<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>['cloudstack']['url']</tt></td>
    <td>String</td>
    <td>The cloudstack API url. Only needed on the manager node.</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['APIkey']</tt></td>
    <td>String</td>
    <td>The cloudstack API key. Only needed on the manager node.</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['SECkey']</tt></td>
    <td>String</td>
    <td>The cloudstack Secret key. Only needed on the manager node.</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['firewall']</tt></td>
    <td>Object</td>
    <td>Contains firewall config</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['firewall']['cleanup']</tt></td>
    <td>Boolean</td>
    <td>
		Should rules not matching node attributes be cleaned up?
		ACLs are only cleaned up when at least one node has specified an ACL in the network
		</td>
    <td><tt>False</tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['firewall']['ingress'][&lt;tag&gt;]</tt></td>
    <td>Array</td>
    <td>Note, use a unique tag per role to prevent roles overwriting each other
    This array holds the actual firewall and portnat rules
    Each of the rules is specified in the following format:
    <table>
      <tr>
        <td>IP address</td>
        <td>Protocol (tcp|udp)</td>
        <td>CIDR block</td>
        <td>Start port public</td>
        <td>End port public</td>
        <td>Start port private<td>
      </tr>
    </table>
    E.g. to specify that external TCP port 80 and 81 on ip 1.2.3.4 have to be allowed publicly and forwarded to port 8080 and 8081 specify:<br>
    [ [ "1.2.3.4", "tcp", "0.0.0.0/0", "80", "81", "8080" ] ]<br>
    </td>
    <td><tt>Empty</tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['acl'][&lt;tag&gt;]</tt></td>
    <td>Array</td>
    <td>Use a unique tag to prevent roles from overwriting firewall rules from other roles
    This array holds the actual network ACL rules for this node
    Each of the rules is specified in the following format:
    <table>
      <tr>
        <td>Network name (or nic_#)</td>
        <td>CIDR block (may contain nic_#)</td>
        <td>Protocol (tcp|udp|icmp)</td>
        <td>Start port or icmp type</td>
        <td>End port or icmp code</td>
        <td>Direction (Ingress|Egress) *Mind the capital*<td>
      </tr>
    </table>
    <ul>
	<li>The keyword nic_# will be replaced with the netowrk the machine is in or the ip address of the machine, if nic_# is found in the network or cidr block field
        <li>Node searches can be specified by using curly braches ({}), e.g. {role:domain_controller}, will expand to a list of chef IP addresses of machines with the role domain controller
    </ul>
    E.g. to specify that on network XXX_p_FRONT 192.168.98.64/26 and 192.168.99.64/26 should be allowed in on tcp port 666 and 667 and all ICMP on the network nic_0 is in, plus to allow tcp and udp 53 from this host specify:<br>
    [ <br>
		&nbsp;&nbsp;	[ "XXX_p_FRONT", "192.168.98.64/26,192.168.99.64/26", "tcp", "666", "667", "Ingress" ], <br>
    &nbsp;&nbsp;  [ "nic_0", "192.168.98.64/26,192.168.99.64/26", "tcp", "666", "667", "Ingress" ], <br>
    &nbsp;&nbsp;  [ "nic_0", "nic_0", "tcp", "53", "53", "Egress" ], <br>
    &nbsp;&nbsp;  [ "nic_0", "nic_0", "udp", "53", "53", "Egress" ] <br>
		]<br>
    </td>
    <td><tt>Empty</tt></td>
  </tr>
</table>

Usage
-----
#### CsFirewall::default
This recipe does nothing, but tells the Firewall manager to read this hosts attributes for firewall input

Just include `CsFirewall` in your node its `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[CsFirewall]"
  ]
}
```

And add rules to the normal attributes:
```json
{
  "cloudstack" : {
    "firewall" :{
      "ingress" : {
        "webserver" : [
          [ "1.2.3.4", "tcp", "0.0.0.0/0", "80", "81", "8080" ]
        ]
      }
    },
    "acl" : {
     "appserver" : [
       [ "XXX_p_FRONT", "192.168.98.64/26,192.168.99.64/26", "tcp", "666", "667", "Ingress" ],
       [ "nic_0", "192.168.98.64/26,192.168.99.64/26", "tcp", "666", "667", "Ingress" ],
       [ "nic_0", "nic_0", "tcp", "53", "53", "Egress" ],
       [ "nic_0", "nic_0", "udp", "53", "53", "Egress" ]
    ]
  }
}
```

#### CsFirewall::manager
This recipe tells the node to manage the Cloud Stack firewall

Just include `CsFirewall::manager` in your node its `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[CsFirewall::manager]"
  ]
}
```

And add configuration attributes
```json
{
  "cloudstack" : {
    "url" : "https://.../client/api",
    "APIkey" : "qmFEFfAr3q-...",
    "SECkey" : "ZOAXv1WLXRfFvxD-..",
    "firewall" :{
      "cleanup" : true
    }
  }
}
```

Contributing
------------
TODO: (optional) If this is a public cookbook, detail the process for contributing. If this is a private cookbook, remove this section.

e.g.
1. Fork the repository on https://github.schubergphilis.com/fbreedijk/CsFirewall
2. Create a named feature branch (like `add_component_x`)
3. Write you change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request using Github

License and Authors
-------------------
Authors: 
* Frank Breedijk <fbreedijk@schubergphilis.com>
