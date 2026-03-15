# require-connectivity

Nix flake providing:

- A package (`require-connectivity`) that continuously checks external connectivity.
- A NixOS module (`services.require-connectivity`) that runs it as a systemd service.
- An overlay exporting the package to `pkgs.require-connectivity`.

If all configured targets are unreachable continuously for a configured duration, the service reboots the machine.

## Defaults

- Down duration before reboot: `5m`
- ICMP targets: `8.8.8.8`, `1.1.1.1`, `8.8.4.4`
- HTTP target: `https://google.com`
- Check interval: `15s`

## Flake Outputs

- `overlays.default` and `overlay`
- `packages.<system>.require-connectivity` and `packages.<system>.default`
- `nixosModules.default` and `nixosModule`

## NixOS Usage

```nix
{
  inputs.require-connectivity.url = "path:/path/to/require-connectivity";

  outputs = { self, nixpkgs, require-connectivity, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        require-connectivity.nixosModules.default
        ({
          services.require-connectivity.enable = true;
        })
      ];
    };
  };
}
```

## Configuration Options

- `services.require-connectivity.enable` (bool)
- `services.require-connectivity.package` (package)
- `services.require-connectivity.checkIntervalSeconds` (int)
- `services.require-connectivity.downDuration` (int or string with `s/m/h/d`, e.g. `"5m"`)
- `services.require-connectivity.icmpTargets` (list of strings)
- `services.require-connectivity.httpTargets` (list of strings)

### Optional Prometheus Metrics

Disabled by default.

- `services.require-connectivity.metrics.enable` (default `false`)
- `services.require-connectivity.metrics.listenAddress` (default `127.0.0.1`)
- `services.require-connectivity.metrics.port` (default `9955`)

When enabled, endpoint is served at:

`http://<listenAddress>:<port>/`

Exported metrics:

- `require_connectivity_seconds_since_connectivity_lost`
- `require_connectivity_last_reboot_was_connectivity`
- `require_connectivity_connectivity_reboots_total`

## Logging Behavior

- Logs when entering the "all checks failing" state.
- Logs when connectivity is restored.
- Emits a `[SHOUT]` log line immediately before triggering reboot due to connectivity loss.
