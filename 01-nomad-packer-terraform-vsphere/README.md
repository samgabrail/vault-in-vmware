# Overview

This is a demo to build a Nomad cluster with Consul in vSphere using Gitlab, Packer, Terraform, and Ansible. The tools are used as follows:

- Packer creates an image template that has docker installed.
- Terraform provisions the VMs to be used in the Nomad and Consul clusters.
- Ansible installs Nomad and Consul into the VMs.
- GitLab is used as the CI/CD pipeline.

## Packer

Run Packer from your computer with the following command:

```bash
cd Packer
packer build -force -on-error=ask -var-file variables.pkrvars100GBdisk.hcl -var-file vsphere.pkrvars.hcl ubuntu-22.04.pkr.hcl
```

## GitLab

We've configured a GitLab pipeline that has 2 stages:
1. Stage 1 - provision: Runs Terraform to provision 6 VMs. 3 for the Nomad servers and 3 for the Nomad clients.
2. Stage 2 - install: Runs Ansible to install Nomad to all 6 servers.

Upon a change in our repo, the pipeline will run automatically. You don't need to run anything manually. You just need to setup ngrok as mentioned below.

## Terraform

Since we're using the free version of Terraform Cloud (TFC), we need a way for TFC to gain access into our vCenter environment. You can do that using TFC cloud agents, but it's a paid feature. We will use a quick and dirty work around using ngrok.

Make sure you have an ngrok account. Then you will need to authenticate your ngrok agent. You only have to do this once. The Authtoken is saved in the default configuration file.

Run the following CLI command from a server running in your environment:

```bash
ngrok config add-authtoken <your_ngrok_auth_token>
```

Now you're ready to open a tunnel to the vCenter server.

Run ngrok using the following CLI command also on a server running in your environment.

```bash
ngrok http https://<the_FQDN_of_your_vCenter_server_or_the_IP> 
```

Here is the output:
```
Session Status                online                                                                                                                                                                           
Account                       Sam Gabrail (Plan: Free)                                                                                                                                                         
Update                        update available (version 3.1.1, Ctrl-U to update)                                                                                                                               
Version                       3.1.0                                                                                                                                                                            
Region                        United States (us)                                                                                                                                                               
Latency                       36ms                                                                                                                                                                             
Web Interface                 http://127.0.0.1:4040                                                                                                                                                            
Forwarding                    https://64b3-2001-1970-5641-ec00-00-7b04.ngrok.io -> https://the_FQDN_of_your_vCenter_server_or_the_IP:443                                                                                                    
                                                                                                                                                                                                               
Connections                   ttl     opn     rt1     rt5     p50     p90                                                                                                                                      
                              53      0       0.01    0.07    90.34   91.54 
```

Now you can use the `64b3-2001-1970-5641-ec00-00-7b04.ngrok.io` hostname as your `vsphere_vcenter` variable in Terraform.

## Ansible

This is the command used by the GitLab pipeline to launch Ansible.

```bash
cd Ansible
ansible-playbook -i inventory playbook.yml
```

## Demo Steps

1. Run Packer to create our Ubuntu 22.04 template image in vSphere and check vSphere to see it there.  

2. Run `ngrok` to give access to TFC to provision our local vSphere environment.

3. In the `.gitlab-ci.yml` file, start with the following variables:

```yml
  SERVER_NAMES: "nomad-consul-server-1"
  CLIENT_NAMES: "nomad-consul-client-1"
  SERVER_IPS: "192.168.1.93"
  CLIENT_IPS: "192.168.1.96"
  # SERVER_NAMES: "nomad-consul-server-1 nomad-consul-server-2 nomad-consul-server-3"
  # CLIENT_NAMES: "nomad-consul-client-1 nomad-consul-client-2 nomad-consul-client-3"
  # SERVER_IPS: "192.168.1.93 192.168.1.94 192.168.1.95"
  # CLIENT_IPS: "192.168.1.96 192.168.1.97 192.168.1.99"
  CONSUL_VERSION: "1.14.1"
  NOMAD_VERSION: "1.4.1"
  CNI_VERSION: "1.1.1"
```

This will use Terraform to provision 2VMs. Then Ansible will configure 1 Nomad/Consul server and 1 Nomad/Consul client with the shown Consul and Nomad versions.

4. Check vSphere to see that we have 2 VMs.

5. Check Consul and Nomad by going to http://192.168.1.93:8500 and http://192.168.1.93:4646, respectively

6. Run the Countdash Nomad job in Nomad and check that it comes up.

7. Check which Nomad client the Dashboard task is running on and go to http://<nomad_client_ip>:9002

8. Update the `.gitlab-ci.yml` file, with the following variables:

```yml
  # SERVER_NAMES: "nomad-consul-server-1"
  # CLIENT_NAMES: "nomad-consul-client-1"
  # SERVER_IPS: "192.168.1.93"
  # CLIENT_IPS: "192.168.1.96"
  SERVER_NAMES: "nomad-consul-server-1 nomad-consul-server-2 nomad-consul-server-3"
  CLIENT_NAMES: "nomad-consul-client-1 nomad-consul-client-2 nomad-consul-client-3"
  SERVER_IPS: "192.168.1.93 192.168.1.94 192.168.1.95"
  CLIENT_IPS: "192.168.1.96 192.168.1.97 192.168.1.99"
  CONSUL_VERSION: "1.14.3"
  NOMAD_VERSION: "1.4.3"
  CNI_VERSION: "1.1.1"
```

This will use Terraform to provision 4 additional VMs. Then Ansible will configure 2 more Nomad/Consul servers and 2 more Nomad/Consul clients with the new upgraded Consul and Nomad versions shown.

9. Check vSphere, Nomad, and Consul to see the increased number of VMs and the updated Nomad and Consul versions.

10. Take a look at the count dashboard to see that it continues to run and count up as we scaled the number of nodes.

11. Destroy the environment by using the following variables in the `.gitlab-ci.yml` file:

```yml
  SERVER_NAMES: ""
  CLIENT_NAMES: ""
  SERVER_IPS: ""
  CLIENT_IPS: ""
  # SERVER_NAMES: "nomad-consul-server-1"
  # CLIENT_NAMES: "nomad-consul-client-1"
  # SERVER_IPS: "192.168.1.93"
  # CLIENT_IPS: "192.168.1.96"
  # SERVER_NAMES: "nomad-consul-server-1 nomad-consul-server-2 nomad-consul-server-3"
  # CLIENT_NAMES: "nomad-consul-client-1 nomad-consul-client-2 nomad-consul-client-3"
  # SERVER_IPS: "192.168.1.93 192.168.1.94 192.168.1.95"
  # CLIENT_IPS: "192.168.1.96 192.168.1.97 192.168.1.99"
  CONSUL_VERSION: "1.14.3"
  NOMAD_VERSION: "1.4.3"
  CNI_VERSION: "1.1.1"
```

## References

- [Ansible roles for Nomad and Consul](https://github.com/manbobo2002/nomad-consul)
