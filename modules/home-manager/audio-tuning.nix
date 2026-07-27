{
  config,
  pkgs,
  ...
}: {
  # Per-laptop speaker tunings (quattro: default/audio/**). omarchy-audio-tuning
  # matches the machine against $OMARCHY_PATH/default/audio/tunings/<model>/ and
  # copies the filter-chain host config + unit into ~/.config.
  home.file.".local/share/omarchy/default/audio" = {
    source = ../../default/audio;
    recursive = true;
  };

  # The unit ships as a file rather than a home-manager service because
  # omarchy-audio-tuning installs and enables it on demand. Nix deviation: the
  # upstream ExecStart is /usr/bin/pipewire.
  home.file.".local/share/omarchy/default/systemd/user/omarchy-speaker-tuning.service".text = ''
    [Unit]
    Description=Omarchy speaker tuning filter-chain
    # WirePlumber does the linking, so starting before it is up risks the output
    # being linked before the speaker device has been discovered.
    After=pipewire.service wireplumber.service
    Requires=pipewire.service
    Wants=wireplumber.service
    # Restart with the audio daemon, since the filter-chain loses its connection
    # when PipeWire goes away.
    PartOf=pipewire.service

    [Service]
    Type=simple
    # Hosts the tuning as a PipeWire *client* rather than loading it into the
    # daemon, so it can be switched without restarting pipewire-pulse (which
    # drops every PulseAudio client's connection).
    ExecStart=${pkgs.pipewire}/bin/pipewire -c omarchy-speaker-tuning.conf
    Restart=on-failure
    RestartSec=2

    [Install]
    WantedBy=graphical-session.target
  '';

  # Taildrop receiver. Upstream enables this from omarchy-install-service-tailscale;
  # tailscale is declarative on NixOS, so gate on the binary being present instead.
  systemd.user.services.omarchy-tailscale-receive = {
    Unit = {
      Description = "Save incoming Taildrop files to the downloads directory";
      ConditionPathExists = "/run/current-system/sw/bin/tailscale";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/share/omarchy/bin/omarchy-tailscale-receive";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
