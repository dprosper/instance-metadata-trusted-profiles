output "IP_ADDRESS" {
  value = ibm_is_floating_ip.floatingip.address
}

output "next_steps" {
  value = <<NEXTSTEPS
  
  ### You can access the trusted profile created for the instance using the IBM Cloud Console UI by the following URL:
        https://cloud.ibm.com/iam/trusted-profiles/iam-${ibm_iam_trusted_profile.iam_trusted_profile.id}?tab=trustrelationship

  ### You can access the VSI ${ibm_is_instance.instance.name} using the following SSH command:
        ssh -i local/build_key_rsa root@${ibm_is_floating_ip.floatingip.address}

  --------------------------------------------------------------------------------
    
NEXTSTEPS
}