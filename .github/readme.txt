This is the terraform infrastructure definition for the COOP Minecraft server.

Long live GUS!

---

Installing a mod:

 - Download the mod (from modrinth preferably)
 - It should be a fabric mod for the right minecraft version
 - Run `sha256sum <modfile>` to get the checksum
 - Edit `scripts/provision-gameserver.sh` with an entry like so:
    ```
    download_mod "<download_url>" "<sha256_checksum>" "[optionally_force_the_filename_if_it_cant_be_inferred_via_header]"
    ```
 - Deregister any existing `minecraft-gameserver` AMIs (and their snapshots)
 - Run `packer build ami/aws-gameserver.pkr.hcl` to create a new AMI with the mod included
 - Copy the resulting AMI ID
 - Edit `modules/proxied_minecraft/gameserver.tf` and replace the old AMI ID for
   `module.minecraft.aws_instance.gameserver` with the new one
 - Run `terraform -chdir=prod apply` to deploy the new AMI to the server
 - Done!

