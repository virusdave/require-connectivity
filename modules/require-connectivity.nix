{ lib, config, pkgs, ... }:
let
  cfg = config.services.require-connectivity;

  durationToSeconds = value:
    if builtins.isInt value then
      value
    else
      let
        matches = builtins.match "^([0-9]+)([smhd]?)$" value;
      in
        if matches == null then
          throw "services.require-connectivity.downDuration must be an integer (seconds) or string like 300, 5m, 2h, 1d"
        else
          let
            magnitude = builtins.fromJSON (builtins.elemAt matches 0);
            unit = builtins.elemAt matches 1;
            factor =
              if unit == "" || unit == "s" then 1
              else if unit == "m" then 60
              else if unit == "h" then 3600
              else if unit == "d" then 86400
              else throw "Unsupported duration unit: ${unit}";
          in
            magnitude * factor;

  downForSeconds = durationToSeconds cfg.downDuration;
in
{
  options.services.require-connectivity = {
    enable = lib.mkEnableOption "periodically require external connectivity and reboot if all checks fail";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.require-connectivity;
      defaultText = lib.literalExpression "pkgs.require-connectivity";
      description = "Package providing the require-connectivity watchdog binary.";
    };

    checkIntervalSeconds = lib.mkOption {
      type = lib.types.int;
      default = 10;
      example = 10;
      description = "Seconds between connectivity checks.";
    };

    downDuration = lib.mkOption {
      type = lib.types.oneOf [ lib.types.int lib.types.str ];
      default = "5m";
      example = "2m";
      description = "How long all checks must fail continuously before reboot. Supports integer seconds or a string with optional units s/m/h/d.";
    };

    icmpTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "8.8.8.8" "1.1.1.1" "8.8.4.4" ];
      description = "ICMP targets checked with ping.";
    };

    httpTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://google.com" ];
      description = "HTTP(S) URLs checked with curl.";
    };

    metrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Export Prometheus metrics endpoint for connectivity watchdog state.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = "Address for the optional metrics HTTP endpoint.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9955;
        description = "Port for the optional metrics HTTP endpoint.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.checkIntervalSeconds > 0;
        message = "services.require-connectivity.checkIntervalSeconds must be > 0";
      }
      {
        assertion = downForSeconds > 0;
        message = "services.require-connectivity.downDuration must resolve to > 0 seconds";
      }
      {
        assertion = (cfg.icmpTargets != [ ]) || (cfg.httpTargets != [ ]);
        message = "services.require-connectivity requires at least one ICMP or HTTP target";
      }
    ];

    systemd.services.require-connectivity = {
      description = "Connectivity watchdog and reboot trigger";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package}";
        Restart = "always";
        RestartSec = 5;
        StateDirectory = "require-connectivity";
      };

      environment = {
        CHECK_INTERVAL_SECONDS = toString cfg.checkIntervalSeconds;
        DOWN_FOR_SECONDS = toString downForSeconds;
        ICMP_TARGETS = lib.concatStringsSep " " cfg.icmpTargets;
        HTTP_TARGETS = lib.concatStringsSep " " cfg.httpTargets;
        STATE_DIR = "/var/lib/require-connectivity";
        METRICS_ENABLED = if cfg.metrics.enable then "1" else "0";
        METRICS_LISTEN_ADDRESS = cfg.metrics.listenAddress;
        METRICS_PORT = toString cfg.metrics.port;
      };
    };
  };
}
