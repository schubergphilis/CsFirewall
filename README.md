CsFirewall Cookbook
===================
This cookbook forces a node to configure the firewall in cloudstack via the 
knife command

Requirements
------------
The knife command has to be installed and runnable as the root user

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
    <td>The cloudstack API url</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['APIkey']</tt></td>
    <td>String</td>
    <td>The cloudstack API key</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['SECkey']</tt></td>
    <td>String</td>
    <td>The cloudstack Secret key</td>
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
    <td>Should rules not matching node attributes be cleaned up?</td>
    <td><tt>False</tt></td>
  </tr>
  <tr>
    <td><tt>['cloudstack']['firewall']['ingress']</tt></td>
    <td>Array</td>
    <td>This array holds the actual firewall and portnat rules
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
    E.g. to specify that external TCP port 80 and 81 on ip 1.2.3.4 have to be allowed publicly and forwarded to port 8080 and 8081 specify:
    [ [ "1.2.3.4", "tcp", "0.0.0.0/0", "80", "81", "8080" ] ]
    </td>
    <td><tt>Empty</tt></td>
  </tr>
</table>

Usage
-----
#### CsFirewall::default
TODO: Write usage instructions for each cookbook.

e.g.
Just include `CsFirewall` in your node's `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[CsFirewall]"
  ]
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
