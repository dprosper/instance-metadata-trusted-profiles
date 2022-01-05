# Create a ssh keypair which will be used to access the VSI for configuration.
resource "tls_private_key" "build_key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

# Add the public key in VPC SSH Keys.
resource "ibm_is_ssh_key" "build_key" {
  name           = "${var.basename}-build-key"
  public_key     = tls_private_key.build_key.public_key_openssh
  resource_group = data.ibm_resource_group.group.id
}

# Saves the public and private SSH key to local disk for debug usage if needed.
resource "local_file" "build_private_key" {
  content         = tls_private_key.build_key.private_key_pem
  filename        = "local/build_key_rsa"
  file_permission = "0600"
}

resource "local_file" "build_public_key" {
  content         = tls_private_key.build_key.public_key_openssh
  filename        = "local/build_key_rsa.pub"
  file_permission = "0600"
}

# Create VSI.
resource "ibm_is_instance" "instance" {
  name           = "${var.basename}-instance"
  vpc            = ibm_is_vpc.vpc.id
  zone           = "${var.region}-1"
  profile        = "cx2-2x4"
  image          = data.ibm_is_image.vsi_image.id
  keys           = [ibm_is_ssh_key.build_key.id]
  resource_group = data.ibm_resource_group.group.id

  primary_network_interface {
    subnet          = ibm_is_subnet.subnet.id
    security_groups = [ibm_is_security_group.group.id]
  }

  # Script file used to create the service on the instance.
  user_data = templatefile("${path.module}/scripts/ssh-authorized-keys-service.sh", {})
}

# Create a Virtual Private Cloud (VPC) Floating IP and assigns to VSI Network Interface.
resource "ibm_is_floating_ip" "floatingip" {
  name   = "${var.basename}-instance-fip"
  target = ibm_is_instance.instance.primary_network_interface[0].id
}

# Creates the trusted profile and links the VSI created earlier as a compute resource.
resource "ibm_iam_trusted_profile" "iam_trusted_profile" {
  name        = "${var.basename}-trusted-profile"
  description = "compute resource trusted profile"
}

# Link the VSI to the trusted profile, providing it the ability to obtain an IAM token.
resource "ibm_iam_trusted_profile_link" "iam_trusted_profile_link" {
  profile_id = ibm_iam_trusted_profile.iam_trusted_profile.id
  cr_type    = "VSI"
  link {
    crn = ibm_is_instance.instance.crn
  }
  name = "${var.basename}-trusted-profile-link"
}

# Creates a policy to allow the newly created instance to read the SSH build key that was added to VPC earlier.
resource "ibm_iam_trusted_profile_policy" "build_key" {
  profile_id = ibm_iam_trusted_profile.iam_trusted_profile.id
  roles      = ["Viewer"]

  resources {
    attributes = {
      "serviceName" = "is"
      "keyId"       = ibm_is_ssh_key.build_key.id
    }
  }
}

# SSH into the VSI to perform configuration of the service.
resource "null_resource" "instance_service_init" {
  connection {
    type        = "ssh"
    host        = ibm_is_floating_ip.floatingip.address
    user        = "root"
    private_key = tls_private_key.build_key.private_key_pem
    agent       = "false"
  }

  # Deploys the configuration for logrotate to rotate the logs created by the ssh-authorized-keys service. 
  provisioner "file" {
    content     = templatefile("${path.module}/scripts/ssh-authorized-keys.conf", {})
    destination = "/etc/logrotate.d/ssh-authorized-keys.conf"
  }

  # Deploys the script that will run as a service and specifies variables such as the trusted profile id and wait time between runs.
  provisioner "file" {
    content = templatefile("${path.module}/scripts/ssh-authorized-keys.sh", {
      profileid        = ibm_iam_trusted_profile.iam_trusted_profile.profile_id
      profilename      = ibm_iam_trusted_profile.iam_trusted_profile.name
      cyclewaitseconds = var.cycle_wait_seconds
    })
    destination = "/usr/bin/ssh-authorized-keys.sh"
  }

  # Initialize the service and sets the logrotate date: https://serverfault.com/a/497671, rotates the first log.
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "chmod +x /usr/bin/ssh-authorized-keys.sh",
      "sed -i.bak 's/\r//g' /usr/bin/ssh-authorized-keys.sh",
      "systemctl enable ssh-authorized-keys",
      "systemctl start ssh-authorized-keys",
      "sleep 30",
      "logrotate -f /etc/logrotate.d/ssh-authorized-keys.conf"
    ]
  }
}