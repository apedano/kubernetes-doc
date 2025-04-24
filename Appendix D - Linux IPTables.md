# Appendix D - Linux IPTables

https://iximiuz.com/en/posts/laymans-iptables-101/

Regards the way network packets are routed inside the linux kernel, according to the following options:

- A packet arrives to the network interface, passes through the network stack and reaches a user space process (internal linux process).

- A packet is created by a user space process, sent to the network stack, and then delivered to the network interface.

- A packet arrives to the network interface and then in accordance with some routing rules is forwarded to another network interface.

## Chains

> A chain is a set of concatenated rules applied to a specific stage of the packet processing.

![iptables-stages-white.png](images%2Fiptables%2Fiptables-stages-white.png)

- **PREROUTING**: altering the packet coming from the network interface, before the routing
- **FORWARD**: altering the packet to be forwarded to another network interface
- **POSTROUTING**: for altering packets as they are about to go out
- **INPUT**: for packets destined to local sockets
- **OUTPUT**: for locally-generated packets to the outgoing network traffic

Example of the first two rules that will be applied in order for the **INPUT** chain 

```bash
# add rule "LOG every packet" to chain INPUT
$ iptables --append INPUT --jump LOG

# add rule "DROP every packet" to chain INPUT
$ iptables --append INPUT --jump DROP
```

## Rules, Targets, Policies

The previous rules are pretty simple, but, in general, they are more complex because
they can access multiple packet attributes (source or destination address or port, protocol etc...)
and define a **target**, being the action to be applied to the packet. 
There are **terminating targets** (`DROP` and `ACCEPT`) that, if encountered put and end to the chain of rules.

```bash
# block packets with source IP 46.36.222.157
# -A is a shortcut for --append
# -j is a shortcut for --jump (set rule target )
$ iptables -A INPUT -s 46.36.222.157 -j DROP

# block outgoing SSH connections
$ iptables -A OUTPUT -p tcp --dport 22 -j DROP

# allow all incoming HTTP(S) connections
$ iptables -A INPUT -p tcp -m multiport --dports 80,443 \
  -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
$ iptables -A OUTPUT -p tcp -m multiport --dports 80,443 \
  -m conntrack --ctstate ESTABLISHED -j ACCEPT
```

If all the chain rules are executed without a terminating target, a default target applies, called **policy**

```bash
# check the default policies
$ sudo iptables --list-rules  # or -S
-P INPUT ACCEPT
-P FORWARD ACCEPT
-P OUTPUT ACCEPT

# change policy for chain FORWARD to target DROP
iptables --policy FORWARD DROP  # or -P
```

> The **rules** of a **chain** are sequentially executed unless a terminating **target** is encountered 
> (DROP, ACCEPT) or it is finished and the **policy**  is applied

#### List of targets

- `-j RETURN`: will cause the current packet to stop traveling through the chain (or sub-chain)
- `-j ACCEPT` : the rule is accepted and will not continue traversing the current chain or any other ones in the same table. Note however, that a packet that was accepted in one chain might still travel through chains within other tables, and could still be dropped there
- `-j DNAT` : only available within PREROUTING and OUTPUT chains in the nat table, and any of the chains called upon from any of those listed chains
- `-j SNAT`: valid only in nat table, within the POSTROUTING chain
- `-j DROP`: Drops the packet, right there right then
- `-j REJECT`: Sends a response back (unlike drop). Valid in the INPUT, FORWARD and OUTPUT chains or their sub chains
- `-j LOG`: Note: Does not work on namespaces. Also can fill up your kernel log.
  ``` iptables` -A INPUT -p tcp -j LOG --log-prefix "INPUT packets"```
- `-j ULOG`: packet information is multicasted together with the whole packet through a netlink socket. One or more user-space processes may then subscribe to various multicast groups and receive the packet
- `-j MARK`: Only valid in mangle table. Note that the mark value is not set within the actual package, but is a value that is associated within the kernel with the packet. In other words does not make it out of the machine
  ```iptables` -t mangle -A PREROUTING -p tcp --dport 22 -j MARK --set-mark 2```
- `-j MASQUERADE`: Similar to SNAT but used on a outbound network interface when the outbound IP can change. Say a DHCP interface Only valid within the POSTROUTING
- `-j REDIRECT`: redirect packets and streams to the machine itself. Valid within the PREROUTING and OUTPUT chains of the nat table. It is also valid within user-defined chains that are only called from those chains

### User defined chains

> Can be considered as a special kind of target, used as a named chain of rules, without a policy (not allowed)

```bash
$ iptables -P INPUT ACCEPT
# drop all forwards by default
$ iptables -P FORWARD DROP
$ iptables -P OUTPUT ACCEPT

# create a new chain
$ iptables -N DOCKER  # or --new-chain

# if outgoing interface is docker0, jump to DOCKER chain
$ iptables -A FORWARD -o docker0 -j DOCKER

# add some specific to Docker rules to the user-defined chain
$ iptables -A DOCKER ...
$ iptables -A DOCKER ...
$ iptables -A DOCKER ...

# jump back to the caller (i.e. FORWARD) chain
$ iptables -A DOCKER -j RETURN 
```

## iptabled Tables

Chains are grouped in tables and multiple tables can define the same chain (for instance INPUT).

`iptables` has five modes of operations (i.e. tables): filter, nat, mangle, raw and security.

Tables change based on the kernel used, but the most commons are

```bash
filter:
    This is the default table (if no -t option is passed). It contains
    the built-in chains INPUT (for packets destined to local sockets),
    FORWARD (for packets being routed through the box), and OUTPUT
    (for locally-generated packets).
nat:
    This table is consulted when a packet that creates a new connection is encountered.
    It consists of three built-ins: PREROUTING (for altering packets as soon as
    they come in), OUTPUT (for altering locally-generated packets before routing),
    and POSTROUTING (for altering packets as they are about to go out). IPv6 NAT support
    is available since kernel 3.7.
mangle:
    This table is used for specialized packet alteration. Until kernel 2.4.17 it had two
    built-in chains: PREROUTING (for altering incoming packets before routing)
    and OUTPUT (for altering locally-generated packets before routing). Since kernel 2.4.18,
    three other built-in chains are also supported: INPUT (for packets coming into the box
    itself), FORWARD (for altering packets being routed through the box), and POSTROUTING
    (for altering packets as they are about to go out).
raw:
    This table is used mainly for configuring exemptions from connection tracking in
    combination with the NOTRACK target. It registers at the netfilter hooks with
    higher priority and is thus called before ip_conntrack, or any other IP tables.
    It provides the following built-in chains: PREROUTING (for packets arriving via
    any network interface) OUTPUT (for packets generated by local processes)
security:
    This table is used for Mandatory Access Control (MAC) networking rules, such as those
    enabled by the SECMARK and CONNSECMARK targets. Mandatory Access Control is implemented
    by Linux Security Modules such as SELinux. The security table is called after the filter
    table, allowing any Discretionary Access Control (DAC) rules in the filter table to take
    effect before MAC rules. This table provides the following built-in chains: INPUT (for
    packets coming into the box itself), OUTPUT (for altering locally-generated packets before
    routing), and FORWARD (for altering packets being routed through the box).
```

![iptables_tables.svg](images%2Fiptables%2Fiptables_tables.svg)


Therefore, we can have overlapping rules.
What will happen to a packet if `filter.INPUT` chain has a DROP target but `mangle.INPUT` chain has an ACCEPT target, both within the affirmative rules

To solve this, there is an order of precedence in tables in the flow to the process space and in the routing

![tables-precedence.png](images%2Fiptables%2Ftables-precedence.png)
![tables-precedence-route.png](images%2Fiptables%2Ftables-precedence-route.png)