{ config, pkgs, ... }:
let
  nixChannel = "https://nixos.org/channels/nixos-24.11"; 
in
{
  zramSwap.enable = true;
  systemd.extraConfig = ''
    DefaultTimeoutStopSec=10s
  '';

  systemd.services."NetworkManager-wait-online".enable = true;

  # Enable and persist Bluetooth
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  # Enable the X11 windowing system.
  #You can disable this if you're only running the Wayland Session
  services.xserver.enable = true;

  # Enable the Cinnamon Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  xdg.portal.enable = true;

  # Enable Printing
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    git
    libnotify
    gawk
    gnugrep
    sudo
    kdePackages.discover
    flatpak
    xdg-desktop-portal
    xdg-desktop-portal-kde
    system-config-printer
  ];

  services.flatpak.enable = true;

  nix.gc = {
    automatic = true;
    dates = "Mon 3:40";
    options = "--delete-older-than 30d";
  };
  
  # Auto update config, flatpak and channel
  systemd.timers."auto-update-config" = {
  wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "auto-update-config.service";
    };
  };

  systemd.services."auto-update-config" = {
    path = with pkgs; [
      git
      nix
      gnugrep
      gawk
      util-linux
      coreutils-full
      flatpak
    ];

    script = ''
      set -eu

      # Update nixbook configs
      git -C /etc/nixbook reset --hard
      git -C /etc/nixbook clean -fd
      git -C /etc/nixbook pull --rebase

      currentChannel=$(nix-channel --list | grep '^nixos' | awk '{print $2}')
      targetChannel="${nixChannel}"

      echo "Current Channel is: $currentChannel"

      if [ "$currentChannel" != "$targetChannel" ]; then
        echo "Updating Nix channel to $targetChannel"
        nix-channel --add "$targetChannel" nixos
        nix-channel --update
      else
        echo "Nix channel is already set to $targetChannel"
      fi
      
      # Flatpak Updates
      nice -n 19 ionice -c 3 flatpak update --noninteractive --assumeyes
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Restart = "on-failure";
      RestartSec = "30s";
    };

    after = [ "network-online.target" "graphical.target" ];
    wants = [ "network-online.target" ];
  };

  # Auto Upgrade NixOS
  systemd.timers."auto-upgrade" = {
  wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      Unit = "auto-upgrade.service";
    };
  };

  systemd.services."auto-upgrade" = {
    path = with pkgs; [
      nixos-rebuild
      nix
      systemd
      util-linux
      coreutils-full
      flatpak
    ];
  
    script = ''
      set -eu
      export NIX_PATH="nixpkgs=${pkgs.path} nixos-config=/etc/nixos/configuration.nix"
      
      systemctl start auto-update-config.service
      nice -n 19 ionice -c 3 nixos-rebuild boot --upgrade

      # Fix for zoom flatpak
      flatpak override --env=ZYPAK_ZYGOTE_STRATEGY_SPAWN=0 us.zoom.Zoom
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Restart = "on-failure";
      RestartSec = "30s";
    };

    after = [ "network-online.target" "graphical.target" ];
    wants = [ "network-online.target" ];
  };
}

# Notes
#
# To reverse zoom flatpak fix:
#   flatpak override --unset-env=ZYPAK_ZYGOTE_STRATEGY_SPAWN us.zoom.Zoom
