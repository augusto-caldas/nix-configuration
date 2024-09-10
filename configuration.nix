{ config, pkgs, ... }:
let
  clientScript = pkgs.writeShellScript "client-script" ''
    case $1 in
      on-batt)
        ${pkgs.util-linux}/bin/logger -t upssched-cmd "UPS On Battery state exceeded timer value."
        ${pkgs.systemd}/bin/shutdown now
        ;;
      *)
        ${pkgs.util-linux}/bin/logger -t upssched-cmd "UPS Unrecognized event: $1"
        ;;
    esac
  '';

  path = "/var/lib/nut";
  
  # UPS Scheduler Configuration
  clientSched = pkgs.writeText "client-schedule" ''
    CMDSCRIPT ${clientScript}

    PIPEFN ${path}/upssched.pipe
    LOCKFN ${path}/upssched.lock

    AT ONBATT * START-TIMER on-batt 60
    AT ONLINE * CANCEL-TIMER on-batt
  '';

  # Shared Configurations
  sharedConf = {
    # User to run
    RUN_AS_USER = "root";
    # Binaries
    SHUTDOWNCMD = "${pkgs.systemd}/bin/shutdown now";
    # Number of power supplies before shutting down
    MINSUPPLIES = 1;
    # Query intervals
    POLLFREQ = 1;
    POLLFREQALERT = 1;
    # Debug
    # DEBUG_MIN = 9;
  };

  # Default Notify
  defaultNotify = "SYSLOG+EXEC";

  # Map Notify Flags
  mapNotifyFlags = listTypes: notification:
    map (each: [ each notification ]) listTypes;

in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  #######
  # UPS #
  #######

  # UPS client
  power.ups = {

    enable = true;
    mode = "netclient";
    schedulerRules = "${clientSched}";

    # UPS Monitor
    upsmon = {

      # Connection
      monitor.main = {
        system = "apc@router";
        powerValue = 1;
        user = "admin";
        passwordFile = "/home/lakituen/.secrets/ups-pass.txt";
        type = "secondary";
      };

      # Settings
      settings = sharedConf // {
        # Binary Scheduler
        NOTIFYCMD = "${pkgs.nut}/bin/upssched";
        # Flags to be notified
        NOTIFYFLAG = mapNotifyFlags [
          "ONLINE" "ONBATT"
        ] defaultNotify;
      };

    };

  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Define hostname
  networking.hostName = "box"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "Europe/Dublin";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.lakituen = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "libvirtd" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.fish;
    packages = with pkgs; [
      htop
      speedtest-cli
      docker-compose
      tmux
      tree
      wget
    ];
  };

  # Enable fish shell
  programs.fish.enable = true;

  # Setup fish shell
  environment.shells = with pkgs; [ fish ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable libvirtd
  virtualisation.libvirtd.enable = true;

  # Setup docker
  virtualisation.docker.enable = true;
  virtualisation.docker.storageDriver = "btrfs";

  # Version system was installed
  system.stateVersion = "23.05";

}
